### UTILITIES FOR LOW-LEVEL MATH ###

#' Convert Hz to semitones
#'
#' Converts from Hz to semitones above C-5 (~0.5109875 Hz). This may not seem very
#' useful, but note that (1) this gives you a nice logarithmic scale for
#' generating natural pitch transitions, (2) with the added benefit of getting
#' musical notation for free from \code{notesDict} (see examples).
#' @param h vector or matrix of frequencies (Hz)
#' @param ref frequency of the reference value (defaults to C-5, 0.51 Hz)
#' @export
#' @examples
#' s = HzToSemitones(c(440, 293, 115))
#' # to convert to musical notation
#' notesDict$note[1 + round(s)]
#' # note the "1 +": semitones ABOVE C0, i.e. notesDict[1, ] is C0
HzToSemitones = function(h, ref = 0.5109875) {
  return(log2(h / ref) * 12)
}

#' Convert semitones to Hz
#'
#' Converts from semitones above C-5 (~0.5109875 Hz) to Hz. See \code{\link{HzToSemitones}}
#' @param s vector or matrix of frequencies (semitones above C0)
#' @param ref frequency of the reference value (defaults to C-5, 0.51 Hz)
#' @export
semitonesToHz = function(s, ref = 0.5109875) {
  return(ref * 2 ^ (s / 12))
}


#' Convert to dB
#'
#' Internal soundgen function.
#' @param x a vector of floats between 0 and 1 (exclusive, i.e. these are ratios)
#' @keywords internal
#' @examples
#' soundgen:::to_dB(c(.1, .5, .75, .9, .95, .99, .999, .9999))
to_dB = function(x) {
  return(10 * log10(x / (1 - x)))
}

#' List depth
#'
#' Internal soundgen function
#'
#' Returns the depth of list structure. See https://stackoverflow.com/questions/13432863/determine-level-of-nesting-in-r
#' @param x any R object
#' @keywords internal
listDepth = function(x) ifelse(is.list(x), 1L + max(sapply(x, listDepth)), 0L)


#' Normalize 0 to 1
#'
#' Internal soundgen function
#'
#' Normalized input vector to range from 0 to 1
#' @param x numeric vector or matrix
#' @keywords internal
zeroOne = function(x) {
  x = x - min(x)
  x = x / max(x)
}

#' log01
#'
#' Internal soundgen function
#'
#' Normalizes, log-transforms, and re-normalizes an input vector, so it ranges
#' from 0 to 1
#' @param v numeric vector
#' @keywords internal
#' @examples
#' v = exp(1:10)
#' soundgen:::log01(v)
log01 = function(v) {
  v = v - min(v) + 1
  v = log(v)
  v = zeroOne(v)
  return(v)
}


#' Simple downsampling
#'
#' Internal soundgen function
#'
#' Takes a numeric vector and downsamples it to the required sampling rate by
#' simply throwing away some of the original points. If the new sampling rate is
#' higher than the original, does nothing.
#' @param s a numeric vector
#' @param srNew the new, required sampling rate
#' @param srOld the original sampling rate
#' @param minLen the minimum length of returned vector
#' @keywords internal
#' @examples
#' s = sort(rnorm(20))
#' soundgen:::downsample(s, srNew = 5, srOld = 18)
#' soundgen:::downsample(s, srNew = 5, srOld = 40)
downsample = function(s, srNew = 10, srOld = 120, minLen = 3){
  if (!srNew < srOld){
    return (s)
  }
  l = length(s)
  dur = l / srOld
  idx = seq(1, l, length.out = min(l, max(minLen, round(dur * srNew))))
  return (s[idx])
}


#' Entropy
#'
#' Internal soundgen function.
#'
#' Returns Weiner or Shannon entropy of an input vector such as a power
#' spectrum. Non-negative input values are recoded as as a small positive number
#' (1e-10). If all elements are zero, returns NA.
#' @param x vector of non-negative floats, e.g. a power spectrum. NB: all
#'   non-negative values are recoded as 1e-10!
#' @param type 'shannon' for Shannon (information) entropy, 'weiner' for Weiner
#'   entropy
#' @param normalize if TRUE, Shannon entropy is normalized by the length of
#'   input vector to range from 0 to 1. It has no affect on Weiner entropy.
#' @return Float between 0 and 1 or NA
#' @keywords internal
#' @examples
#' # Here are four simplified power spectra, each with 9 frequency bins:
#' s = list(
#'   c(rep(0, 4), 1, rep(0, 4)),       # a single peak in spectrum
#'   c(0, 0, 1, 0, 0, .75, 0, 0, .5),  # perfectly periodic, with 3 harmonics
#'   rep(0, 9),                        # a silent frame
#'   rep(1, 9)                         # white noise
#' )
#'
#' # Weiner entropy is ~0 for periodic, NA for silent, 1 for white noise
#' sapply(s, function(x) round(soundgen:::getEntropy(x), 2))
#'
#' # Shannon entropy is ~0 for periodic with a single harmonic, moderate for
#' # periodic with multiple harmonics, NA for silent, highest for white noise
#' sapply(s, function(x) round(soundgen:::getEntropy(x, type = 'shannon'), 2))
#'
#' # Normalized Shannon entropy - same but forced to be 0 to 1
#' sapply(s, function(x) round(soundgen:::getEntropy(x,
#'   type = 'shannon', normalize = TRUE), 2))
getEntropy = function(x, type = c('weiner', 'shannon')[1], normalize = FALSE) {
  if (sum(x) == 0) return (NA)  # empty frames
  x = ifelse (x <= 0, 1e-10, x)  # otherwise log0 gives NaN
  if (type == 'weiner') {
    geom_mean = exp(mean(log(x)))
    ar_mean = mean(x)
    entropy = geom_mean / ar_mean
  } else if (type == 'shannon') {
    p = x / sum(x)
    if (normalize) {
      entropy = -sum(p * log2(p) / log(length(p)) * log(2))
    } else {  # unnormalized
      entropy = -sum(p * log2(p))
    }
  } else {
    stop('Implemented entropy types: "shannon" or "weiner"')
  }
  return (entropy)
}


#' Random draw from a truncated normal distribution
#'
#' \code{rnorm_bounded} generates random numbers from a normal distribution
#' using rnorm(), but forced to remain within the specified low/high bounds. All
#' proposals outside the boundaries (exclusive) are discarded, and the sampling
#' is repeated until there are enough values within the specified range. Fully
#' vectorized.
#'
#' @param n the number of values to return
#' @param mean the mean of the normal distribution from which values are
#'   generated (vector of length 1 or n)
#' @param sd the standard deviation of the normal distribution from which values
#'   are generated (vector of length 1 or n)
#' @param low,high exclusive lower and upper bounds ((vectors of length 1 or n))
#' @param roundToInteger boolean vector of length 1 or n. If TRUE, the
#'   corresponding value is rounded to the nearest integer.
#' @return A vector of length n.
#' @keywords internal
#' @examples
#' soundgen:::rnorm_bounded(n = 3, mean = 10, sd = 5, low = 7, high = NULL,
#'   roundToInteger = c(TRUE, FALSE, FALSE))
#' soundgen:::rnorm_bounded(n = 9, mean = c(10, 50, 100), sd = c(5, 0, 20),
#'   roundToInteger = TRUE) # vectorized
rnorm_bounded = function(n = 1,
                         mean = 0,
                         sd = 1,
                         low = NULL,
                         high = NULL,
                         roundToInteger = FALSE) {
  if (length(mean) < n) mean = spline(mean, n = n)$y
  if (length(sd) < n) sd = spline(sd, n = n)$y
  sd[sd < 0] = 0

  if (any(mean > high | mean < low)) {
    warning(paste('Some of the specified means are outside the low/high bounds!',
            'Mean =', paste(mean, collapse = ', '),
            'Low =', paste(low, collapse = ', '),
            'High = ', paste(high, collapse = ', ')))
    mean[mean < low] = low
    mean[mean > high] = high
  }

  if (sum(sd != 0) == 0) {
    out = mean
    out[roundToInteger] = round(out[roundToInteger], 0)
    return (out)
  }

  if (is.null(low) & is.null(high)) {
    out = rnorm(n, mean, sd)
    out[roundToInteger] = round (out[roundToInteger], 0)
    return (out)
  }

  if (is.null(low)) low = rep(-Inf, n)
  if (is.null(high)) high = rep(Inf, n)
  if (length(low) == 1) low = rep(low, n)
  if (length(high) == 1) high = rep(high, n)

  out = rnorm(n, mean, sd)
  out[roundToInteger] = round (out[roundToInteger], 0)
  for (i in 1:n) {
    while (out[i] < low[i] | out[i] > high[i]) {
      out[i] = rnorm(1, mean[i], sd[i]) # repeat until a suitable value is generated
      out[roundToInteger] = round(out[roundToInteger], 0)
    }
  }
  return(out)
}


#' Modified mode
#'
#' Internal soundgen function
#'
#' Internal helper function for spectral (~BaNa) pitch tracker. NOT quite the same as simply mode(x).
#' @param x numeric vector
#' @keywords internal
#' @examples
#' soundgen:::Mode(c(1, 2, 3))  # if every element is unique, return the smallest
#' soundgen:::Mode(c(1, 2, 2, 3))
Mode = function(x) {
  x = sort(x)
  ux = unique(x)
  if (length(ux) < length(x)) {
    return(ux[which.max(tabulate(match(x, ux)))])
  } else {
    # if every element is unique, return the smallest
    return(x[1])
  }
}


#' Random walk
#'
#' Internal soundgen function.
#'
#' Generates a random walk with flexible control over its range, trend, and
#' smoothness. It works by calling \code{\link[stats]{rnorm}} at each step and
#' taking a cumulative sum of the generated values. Smoothness is controlled by
#' initially generating a shorter random walk and upsampling.
#' @param len an integer specifying the required length of random walk. If len
#'   is 1, returns a single draw from a gamma distribution with mean=1 and
#'   sd=rw_range
#' @param rw_range the upper bound of the generated random walk (the lower bound
#'   is set to 0)
#' @param rw_smoothing specifies the amount of smoothing, from 0 (no smoothing)
#'   to 1 (maximum smoothing to a straight line)
#' @param method specifies the method of smoothing: either linear interpolation
#'   ('linear', see \code{\link[stats]{approx}}) or cubic splines ('spline', see
#'   \code{\link[stats]{spline}})
#' @param trend mean of generated normal distribution (vectors are also
#'   acceptable, as long as their length is an integer multiple of len). If
#'   positive, the random walk has an overall upwards trend (good values are
#'   between 0 and 0.5 or -0.5). Trend = c(1,-1) gives a roughly bell-shaped rw
#'   with an upward and a downward curve. Larger absolute values of trend
#'   produce less and less random behavior
#' @return Returns a numeric vector of length len and range from 0 to rw_range.
#' @keywords internal
#' @examples
#' plot(soundgen:::getRandomWalk(len = 1000, rw_range = 5,
#'   rw_smoothing = .2))
#' plot(soundgen:::getRandomWalk(len = 1000, rw_range = 15,
#'   rw_smoothing = .2, trend = c(.5, -.5)))
#' plot(soundgen:::getRandomWalk(len = 1000, rw_range = 15,
#'   rw_smoothing = .2, trend = c(15, -1)))
getRandomWalk = function(len,
                         rw_range = 1,
                         rw_smoothing = .2,
                         method = c('linear', 'spline')[2],
                         trend = 0) {
  if (len < 2)
    return (rgamma(1, 1 / rw_range ^ 2, 1 / rw_range ^ 2))

  # generate a random walk (rw) of length depending on rw_smoothing,
  # then linear extrapolation to len
  n = floor(max(2, 2 ^ (1 / rw_smoothing)))
  if (length(trend) > 1) {
    n = round(n / 2, 0) * 2 # force to be even
    trend_short = rep(trend, each = n / length(trend))
    # for this to work, length(trend) must be a multiple of n.
    # In practice, specify trend of length 2
  } else {
    trend_short = trend
  }

  if (n > len) {
    rw_long = cumsum(rnorm(len, trend_short)) # just a rw of length /len/
  } else {
    # get a shorter sequence and extrapolate, thus achieving
    # more or less smoothing
    rw_short = cumsum(rnorm(n, trend_short)) # plot(rw_short, type = 'l')
    if (method == 'linear') {
      rw_long = approx(rw_short, n = len)$y
    } else if (method == 'spline') {
      rw_long = spline(rw_short, n = len)$y
    }
  } # plot (rw_long, type = 'l')

  # normalize
  rw_normalized = rw_long - min(rw_long)
  rw_normalized = rw_normalized / max(abs(rw_normalized)) * rw_range
  return (rw_normalized)
}


#' Discrete random walk
#'
#' Internal soundgen function.
#'
#' Takes a continuous random walk and converts it to continuous epochs of
#' repeated values 0/1/2, each at least minLength points long. 0/1/2 correspond
#' to different noise regimes: 0 = no noise, 1 = subharmonics, 2 = subharmonics
#' and jitter/shimmer.
#' @keywords internal
#' @param rw a random walk generated by \code{\link{getRandomWalk}} (expected
#'   range 0 to 100)
#' @param nonlinBalance a number between 0 to 100: 0 = returns all zeros;
#'   100 = returns all twos
#' @param minLength the mimimum length of each epoch
#' @param plot if TRUE, plots the random walk underlying nonlinear regimes
#' @return Returns a vector of integers (0/1/2) of the same length as rw.
#' @keywords internal
#' @examples
#' rw = soundgen:::getRandomWalk(len = 100, rw_range = 100, rw_smoothing = .2)
#' r = soundgen:::getIntegerRandomWalk(rw, nonlinBalance = 75,
#'                                      minLength = 10, plot = TRUE)
#' r = soundgen:::getIntegerRandomWalk(rw, nonlinBalance = 15,
#'                                      minLength = 10, plot = TRUE)
getIntegerRandomWalk = function(rw,
                                nonlinBalance = 50,
                                minLength = 50,
                                plot = FALSE) {
  len = length(rw)
  if (nonlinBalance == 0) return(rep(0, len))
  if (nonlinBalance == 100) return(rep(2, len))

  # calculate thresholds for different noise regimes
  q1 = noiseThresholdsDict$q1[nonlinBalance + 1]
  # +1 b/c the rows indices in noiseThresholdsDict start from 0, not 1
  q2 = noiseThresholdsDict$q2[nonlinBalance + 1]

  # convert continuous rw to discrete epochs based on q1 and q2 thresholds
  rw_bin = rep(0, len)
  rw_bin[which(rw > q1)] = 1
  rw_bin[which(rw > q2)] = 2   # plot (rw_bin, ylim=c(0,2))

  # make sure each epoch is long enough
  rw_bin = clumper(rw_bin, minLength = minLength)

  if (FALSE) {
    rw_bin_100 = rw_bin
    rw_bin_100[rw_bin_100 == 1] = q1
    rw_bin_100[rw_bin_100 == 2] = q2

    plot(rw, ylim = c(0, 110), type = 'l', lwd = 1,
         xlab = 'Time', ylab = 'Latent non-linearity', main = 'Random walk')
    points(rw_bin_100, type = 'l', lwd = 4, col = 'blue')
    lines(x = c(0, 100), y = c(q1, q1), lty = 3, lwd = 2, col = 'red')
    text(x = 0, y = q1 + 2, labels = 'subh', pos = 4)
    lines(x = c(0, 100), y = c(q2, q2), lty = 3, lwd = 2, col = 'red')
    text(x = 0, y = q2 + 2, labels = 'subh + jitter', pos = 4)
  }
  return(rw_bin)
}



#' Resize vector to required length
#'
#' Internal soundgen function.
#'
#' Adjusts a vector to match the required length by either trimming one or both
#' ends or padding them with zeros.
#' @param myseq input vector
#' @param len target length
#' @param padDir specifies the affected side. For padding, it is the side on
#'   which new elements will be added. For trimming, this is the side that will
#'   be trimmed. Defaults to 'central'
#' @param padWith if the vector needs to be padded to match the required length,
#'   what should it be padded with? Defaults to 0
#' @return Returns the modified vector of the required length.
#' @keywords internal
#' @examples
#' soundgen:::matchLengths(c(1, 2, 3), len = 5)
#' soundgen:::matchLengths(3:7, len = 3)
#' # trimmed on the left
#' soundgen:::matchLengths(3:7, len = 3, padDir = 'left')
#' # padded with zeros on the left
#' soundgen:::matchLengths(3:7, len = 30, padDir = 'left')
matchLengths = function(myseq,
                        len,
                        padDir = c('left', 'right', 'central')[3],
                        padWith = 0) {
  #  padDir specifies where to cut/add zeros ('left' / 'right' / 'central')
  if (length(myseq) == len) return (myseq)

  if (padDir == 'central') {
    if (length(myseq) < len) {
      myseq = c(rep(padWith, len), myseq, rep(padWith, len))
      # for padding, first add a whole lot of zeros and then trim using the same
      # algorithm as for trimming
    }
    halflen = len / 2
    center = (1 + length(myseq)) / 2
    start = ceiling(center - halflen)
    myseq = myseq[start:(start + len - 1)]
  } else if (padDir == 'left') {
    if (length(myseq) > len) {
      myseq = myseq [(length(myseq) - len + 1):length(myseq)]
    } else {
      myseq = c(rep(padWith, (len - length(myseq))), myseq)
    }
  } else if (padDir == 'right') {
    if (length(myseq) > len) {
      myseq = myseq [1:(length(myseq) - len)]
    } else {
      myseq = c(myseq, rep(padWith, (len - length(myseq))))
    }
  }
  return (myseq)
}


#' Match number of columns
#'
#' Internal soundgen function
#'
#' Adds columns of zeros or NA to a matrix (attaching them both left and
#' right), so that the new number of columns = \code{len}
#' @param matrix_short input matrix
#' @param nCol the required number of columns
#' @param padWith the value to pad with, normally \code{0} or \code{NA}
#' @keywords internal
#' @examples
#' a = matrix(1:9, nrow = 3)
#' soundgen:::matchColumns(a, nCol = 6, padWith = NA)
matchColumns = function (matrix_short, nCol, padWith = 0) {
  col_short = 1:ncol(matrix_short)
  # pads with zeros/NA etc right and left
  col_long = matchLengths(col_short, nCol,
                          padDir = 'central', padWith = padWith)
  new = matrix(padWith,
               nrow = nrow(matrix_short),
               ncol = length(col_long))
  colnames(new) = col_long
  if (is.na(padWith)) {
    new[, !is.na(colnames(new))] = matrix_short
  } else {
    new[, colnames(new) != padWith] = matrix_short
    # paste the old matrix where it belongs, fill the rest with zeros, NA's etc
  }
  return (new)
}


#' Add overlapping vectors
#'
#' Adds two partly overlapping vectors, such as two waveforms, to produce a
#' longer vector. The location at which vector 2 is pasted is defined by
#' insertionPoint. Algorithm: both vectors are padded with zeros to match in
#' length and then added. All NA's are converted to 0.
#' @param v1,v2 numeric vectors
#' @param insertionPoint the index of element in vector 1 at which vector 2 will
#'   be inserted (any integer, can also be negative)
#' @export
#' @examples
#' v1 = 1:6
#' v2 = rep(100, 3)
#' addVectors(v1, v2, insertionPoint = 5)
#' addVectors(v1, v2, insertionPoint = -4)
#' # note the asymmetry: insertionPoint refers to the first arg
#' addVectors(v2, v1, insertionPoint = -4)
#'
#' v3 = rep(100, 15)
#' addVectors(v1, v3, insertionPoint = -4)
#' addVectors(v2, v3, insertionPoint = 7)
addVectors = function(v1, v2, insertionPoint) {
  if (!is.numeric(v1)) stop(paste('Non-numeric v1:', head(v1)))
  if (!is.numeric(v2)) stop(paste('Non-numeric v2:', head(v2)))
  v1[is.na(v1)] = 0
  v2[is.na(v2)] = 0

  # align left ends
  if (insertionPoint > 1) {
    pad_left = insertionPoint - 1
    v2 = c(rep(0, insertionPoint), v2)
  } else if (insertionPoint < 1) {
    pad_left = 1 - insertionPoint
    v1 = c(rep(0, pad_left), v1)
  }

  # equalize lengths
  l1 = length(v1)
  l2 = length(v2)
  len_dif = l2 - l1
  if (len_dif > 0) {
    v1 = c(v1, rep(0, len_dif))
  } else if (len_dif < 0) {
    v2 = c(v2, rep(0, -len_dif))
  }

  return (v1 + v2)
}


#' Clump a sequence into large segments
#'
#' Internal soundgen function.
#'
#' \code{clumper} makes sure each homogeneous segment in a sequence is at least
#' minLength long. Called by getIntegerRandomWalk() and getVocalFry(). Algorithm:
#' go through the sequence once. If a short segment is encountered, it is pooled
#' with the previous one (i.e., the currently evaluated segment grows until it
#' is long enough, which may shorten the following segment). Finally, the last
#' segment is checked separately. This is CRUDE - a smart implementation is
#' pending!
#' @keywords internal
#' @param s a vector (soundgen supplies integers, but \code{clumper} also works
#'   on a vector of floats, characters or booleans)
#' @param minLength an integer or vector of integers indicating the desired
#'   length of a segment at each position (can vary with time, e.g., if we are
#'   processing pitch_per_gc values)
#' @return Returns the original sequence s transformed to homogeneous segments
#'   of required length.
#' @keywords internal
#' @examples
#' s = c(1,3,2,2,2,0,0,4,4,1,1,1,1,1,3,3)
#' soundgen:::clumper(s, 2)
#' soundgen:::clumper(s, 3)
#' soundgen:::clumper(s, seq(1, 3, length.out = length(s)))
#' soundgen:::clumper(c('a','a','a','b','b','c','c','c','a','c'), 4)
clumper = function(s, minLength) {
  if (max(minLength) < 2) return(s)
  minLength = round(minLength) # just in case it's not all integers
  if (length(unique(s)) < 2 |
      (length(minLength) == 1 && length(s) < minLength) |
      length(s) < minLength[1]) {
    return(rep(round(median(s)), length(s)))
  }
  if (length(minLength)==1 |length(minLength)!=length(s)) {
    minLength = rep(minLength, length(s)) # upsample minLength
  }

  c = 0
  for (i in 2:length(s)) {
    if (s[i - 1] == s[i]) {
      c = c + 1
    } else {
      if (c < minLength[i]) {
        s[i] = s[i - 1] # grow the current segment until it is long enough
        c = c + 1
      } else {
        c = 1 # terminate the segment and reset the counter
      }
    }
  }

  # make sure the last epoch is also long enough
  idx_min = max((length(s) - tail(minLength, 1) + 1), 2):length(s)
  # these elements have to be homogeneous
  if (sum(s[idx_min] == tail(s, 1)) < tail(minLength, 1)) {
    # if they are not...
    idx = rev(idx_min)
    c = 1
    i = 2
    while (s[idx[i]] == s[idx[i] - 1] & i < length(idx)) {
      # count the number of repetitions for the last element
      c = c + 1
      i = i + 1
    }
    if (c < tail(minLength, 1)) {
      # if this number is insufficient,...
      s[idx] = s[min(idx_min)] # ...pool the final segment and the previous one
    }
  } # plot (s)
  return(s)
}


#' Simple peak detection
#'
#' Internal soundgen function.
#'
#' Peak detection with \code{\link[zoo]{rollapply}}. Less versatile but x 10
#' faster than \code{\link[seewave]{fpeaks}}.
#' @param x input vector
#' @param threshold threshold for peak detection
#' @keywords internal
#' @examples
#' soundgen:::isCentral.localMax(c(1,1,3,2,1), 2.5)
isCentral.localMax = function(x, threshold) {
  middle = ceiling(length(x) / 2)
  return(which.max(x) == middle & x[middle] > threshold)
}


#' Get sigmoid filter
#'
#' Internal soundgen function.
#'
#' Produces a filter for amplitude modulation ranging from clicks to
#' approximately a sine wave to reversed clicks (small episodes of silence). The
#' filter is made from concatenated sigmoids and their mirror reflections.
#' @return Returns a vector of length \code{len} and range from 0 to 1
#' @param len the length of output vector
#' @param samplingRate the sampling rate of the output vector, Hz
#' @param freq the frequency of amplitude modulation, Hz (numeric vector)
#' @param shape 0 = ~sine, -1 = clicks, +1 = notches (NB: vice versa in
#'   soundgen!); numeric vector of length 1 or the same length as \code{freq}
#' @param spikiness the larger, the more quickly the shape of filter leaves;
#'   numeric vector of length 1 or the same length as \code{freq}
#'   sine-like approximation as shape deviates from 0
#' @examples
#' for (shape in c(0, -.1, .1, -1, 1)) {
#'   s = soundgen:::getSigmoid(shape = shape, len = 1000, samplingRate = 500,  freq = 2)
#'   plot(s, type = 'l',  main = paste('shape =', shape), xlab = '', ylab = '')
#' }
getSigmoid = function(len,
                      samplingRate = 16000,
                      freq = 5,
                      shape = 0,
                      spikiness = 1) {
  # print(c(len, freq))
  if (length(freq) > 1 | length(shape) > 1 | length(spikiness) > 1) {
    # get preliminary frequency contour to estimate how many cycles are needed
    freqContour_prelim = getSmoothContour(anchors = freq, len = 100, valueFloor = 0.001, method = 'spline')
    # plot(freqContour_prelim, type = 'l')
    n = ceiling(len / samplingRate / mean(1 / freqContour_prelim))

    # get actual contours
    freqContour = getSmoothContour(anchors = freq, len = n, valueFloor = 0.001, method = 'spline')
    shapeContour = getSmoothContour(anchors = shape, len = n, method = 'spline')
    spikinessContour = getSmoothContour(anchors = spikiness, len = n, method = 'spline')

    # set up par vectors
    from = -exp(-shapeContour * spikinessContour)
    to = exp(shapeContour * spikinessContour)
    slope = exp(abs(shapeContour)) * 5  # close to sine

    # create one cycle at a time
    out = vector()
    i = 1
    while (length(out) < len) {
      a = seq(from = from[i], to = to[i], length.out = samplingRate / freqContour[i] / 2)
      b = 1 / (1 + exp(-a * slope[i]))
      b = zeroOne(b)  # plot(b, type = 'l')
      out = c(out, b, rev(b))
      i = ifelse(i + 1 > n, n, i + 1)  # repeat the last value if we run out of cycles
    }
    out = out[1:len]
  } else {
    # if pars are static, we can take a shortcut (~50 times faster)
    from = -exp(-shape * spikiness)
    to = exp(shape * spikiness)
    slope = exp(abs(shape)) * 5  # close to sine
    a = seq(from = from, to = to, length.out = samplingRate / freq / 2)
    b = 1 / (1 + exp(-a * slope))
    b = zeroOne(b)  # plot(b, type = 'l')
    out = rep(c(b, rev(b)), length.out = len)
  }
  # plot(out, type = 'l')
  return(out)
}

