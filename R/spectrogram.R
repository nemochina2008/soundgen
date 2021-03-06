### FUNCTIONS FOR PREPARING AND PLOTTING A SPECTROGRAM ###

#' Spectrogram
#'
#' Produces the spectrogram of a sound using short-term Fourier transform. This
#' is a simplified version of \code{\link[seewave]{spectro}} with fewer plotting
#' options, but with added routines for noise reduction, smoothing in time and
#' frequency domains, and controlling contrast and brightness.
#' @param x path to a .wav file or a vector of amplitudes with specified
#'   samplingRate
#' @param samplingRate sampling rate of \code{x} (only needed if
#'   \code{x} is a numeric vector, rather than a .wav file)
#' @param windowLength length of FFT window, ms
#' @param overlap overlap between successive FFT frames, \%
#' @param step you can override \code{overlap} by specifying FFT step, ms
#' @param wn window type: gaussian, hanning, hamming, bartlett, rectangular,
#'   blackman, flattop
#' @param zp window length after zero padding, points
#' @param smoothFreq,smoothTime length of the window, in data points (0 to
#'   +inf), for calculating a rolling median. Applies median smoothing to
#'   spectrogram in frequency and time domains, respectively
#' @param qTime the quantile to be subtracted for each frequency
#'   bin. For ex., if qTime = 0.5, the median of each frequency
#'   bin (over the entire sound duration) will be calculated and subtracted from
#'   each frame (see examples)
#' @param percentNoise percentage of frames (0 to 100\%) used for calculating noise
#'   spectrum
#' @param noiseReduction how much noise to remove (0 to +inf, recommended 0 to
#'   2). 0 = no noise reduction, 2 = strong noise reduction: \eqn{spectrum -
#'   (noiseReduction * noiseSpectrum)}, where noiseSpectrum is the average
#'   spectrum of frames with entropy exceeding the quantile set by
#'   \code{percentNoise}
#' @param contrast spectrum is exponentiated by contrast (-inf to +inf,
#'   recommended -1 to +1). Contrast >0 increases sharpness, <0 decreases
#'   sharpness
#' @param brightness how much to "lighten" the image (>0 = lighter, <0 = darker)
#' @param method plot spectrum ('spectrum') or the first time derivative of the
#'   spectrum ('spectralDerivative')
#' @param output specifies what to return: nothing ('none'), unmodified
#'   spectrogram ('original'), or denoised and/or smoothed spectrogram
#'   ('processed')
#' @param ylim frequency range to plot, kHz (defaults to 0 to Nyquist frequency)
#' @param plot should a spectrogram be plotted? TRUE / FALSE
#' @param osc should an oscillogram be shown under the spectrogram? TRUE / FALSE
#' @param colorTheme black and white ('bw'), as in seewave package ('seewave'),
#'   or another color theme (e.g. 'heat.colors')
#' @param xlab label for x-axis
#' @param ... other graphical parameters passed to
#'   \code{seewave:::filled.contour.modif2}
#' @param frameBank ignore (only needed for pitch tracking)
#' @param duration ignore (only needed for pitch tracking)
#' @export
#' @return Returns nothing (if output = 'none'), raw spectrum (if output =
#'   'original'), denoised and/or smoothed spectrum (if output = 'processed'),
#'   or spectral derivatives (if method = 'spectralDerivative') as a matrix of
#'   real numbers.
#' @examples
#' # synthesize a sound 1 s long, with gradually increasing hissing noise
#' sound = soundgen(sylLen = 1000, temperature = 0, noiseAnchors = list(
#'   time = c(0, 1300), value = c(-120, 0)), formantsNoise = list(
#'   f1 = list(time = 0, freq = 5000, width = 10000, amp = 0)))
#' # playme(sound, samplingRate = 16000)
#'
#' # basic spectrogram
#' spectrogram(sound, samplingRate = 16000)
#'
#' \dontrun{
#' # add an oscillogram
#' spectrogram(sound, samplingRate = 16000, osc = TRUE)
#' # broad-band instead of narrow-band
#' spectrogram(sound, samplingRate = 16000, windowLength = 5)
#' # spectral derivatives
#' spectrogram(sound, samplingRate = 16000, method = 'spectralDerivative')
#'
#' # focus only on values in the upper 5% for each frequency bin
#' spectrogram(sound, samplingRate = 16000, qTime = 0.95)
#'
#' # detect 10% of the noisiest frames based on entropy and remove the pattern
#' # found in those frames (in this cases, breathing)
#' spectrogram(sound, samplingRate = 16000,  noiseReduction = 1.1,
#'   brightness = -2)  # white noise almost gone
#'
#' # apply median smoothing in both time and frequency domains
#' spectrogram(sound, samplingRate = 16000, smoothFreq = 5,
#'   smoothTime = 5)
#'
#' # increase contrast, reduce brightness
#' spectrogram(sound, samplingRate = 16000, contrast = 1, brightness = -1)
#'
#' # add bells and whistles
#' spectrogram(sound, samplingRate = 16000, osc = TRUE, noiseReduction = 1.1,
#'   brightness = -1, colorTheme = 'heat.colors', xlab = 'Time, ms',
#'   ylab = 'Frequency, kHz', ylim = c(0,5))
#' }
spectrogram = function(x,
                       samplingRate = NULL,
                       windowLength = 50,
                       step = NULL,
                       overlap = 70,
                       wn = 'gaussian',
                       zp = 0,
                       smoothFreq = 0,
                       smoothTime = 0,
                       qTime = 0,
                       percentNoise = 10,
                       noiseReduction = 0,
                       contrast = .2,
                       brightness = 0,
                       method = c('spectrum', 'spectralDerivative')[1],
                       output = c('none', 'original', 'processed')[1],
                       ylim = NULL,
                       plot = TRUE,
                       osc = FALSE,
                       colorTheme = c('bw', 'seewave', '...')[1],
                       xlab = '',
                       frameBank = NULL,
                       duration = NULL,
                       ...) {
  if (is.null(step)) step = windowLength * (1 - overlap / 100)
  # import audio
  if (class(x) == 'character') {
    sound_wav = tuneR::readWave(x)
    samplingRate = sound_wav@samp.rate
    windowLength_points = floor(windowLength / 1000 * samplingRate / 2) * 2
    sound = sound_wav@left
    duration = length(sound) / samplingRate
    frameBank = getFrameBank (
      sound = sound,
      samplingRate = samplingRate,
      windowLength_points = windowLength_points,
      step = step,
      zp = zp,
      wn = wn,
      filter = NULL
    )
  } else if (class(x) == 'numeric' & length(x) > 1) {
    if (is.null(samplingRate)) {
      stop ('Please specify samplingRate, eg 44100')
    } else {
      sound = x
      duration = length(sound) / samplingRate
      windowLength_points = floor(windowLength / 1000 * samplingRate / 2) * 2
      frameBank = getFrameBank (
        sound = x,
        samplingRate = samplingRate,
        windowLength_points = windowLength_points,
        step = step,
        zp = zp,
        wn = wn,
        filter = NULL
      )
    }
  }
  if (class(frameBank) != 'matrix') {
    stop(
      'Input format not recognized. Please provide path to .wav file,
      a vector of amplitudes plus samplingRate, or a preprocessed frameBank'
    )
  }

  # fix default settings
  if (is.null(ylim)) {
    ylim = c(0, floor(samplingRate / 2 / 1000))
  }
  contrast_exp = exp(3 * contrast)
  brightness_exp = exp(3 * brightness)
  # visualization: plot(exp(3 * seq(-1, 1, by = .01)), type = 'l')

  # FFT
  windowLength_points = floor(windowLength / 1000 * samplingRate / 2) * 2
  # fft of each frame
  z = apply(frameBank, 2, function(x) stats::fft(x)[1:(floor(nrow(frameBank) / 2))])
  X = seq(0, duration * 1000, length.out = ncol(z))  # time stamp
  Y = seq(0,
          (samplingRate / 2) - (samplingRate / windowLength_points),
          length.out = nrow(z)) / 1000  # frequency stamp
  rownames(z) = Y
  colnames(z) = X
  Z = t(abs(z))

  if (method == 'spectralDerivative') {
    # first derivative of spectrum by time
    dZ_dt = cbind (rep(0, nrow(Z)), t(apply(Z, 1, diff)))
    # first derivative of spectrum by frequency
    dZ_df = rbind (rep(0, ncol(Z)), apply(Z, 2, diff))
    Z1 = sqrt(dZ_dt ^ 2 + dZ_df ^ 2)  # length of gradient vector
  } else {
    Z1 = Z # this is our raw spectrogram
  }

  # removing noise. NB: the order of these operations is crucial,
  # don't change it!
  if (smoothTime > 1) {
    Z1 = t(apply(Z1, 1, function(x) {
      zoo::rollmedian(x, k = smoothTime, fill = 0)
    }))  # time domain
  }
  if (smoothFreq > 1) {
    Z1 = apply(Z1, 2, function(x) {
      zoo::rollmedian(x, k = smoothFreq, fill = 0)
    }) # freq domain
  }
  if (qTime > 0) {
    Z1 = t(apply(Z1, 1, function(x) {
      x - quantile(x, probs = qTime)
    }))  # for each freq bin, subtract median or another quantile
  }

  # re-normalize
  positives = which(Z1 > 0)
  nonpositives = which(Z1 <= 0)
  Z1[positives] = log(Z1[positives])
  Z1[nonpositives] = min(Z1[positives])
  Z1 = Z1 - min(Z1)

  if (noiseReduction > 0) {
    # silence frames with entropy above threshold
    entr = apply(Z1, 1, function(x) getEntropy(x)) # Z1 >= 0
    q = quantile(entr, probs = 1 - percentNoise/100, na.rm = TRUE) # the entropy of
    # silent frames is NA
    # plot(entr, type='l'); lines(x=1:length(entr),y=rep(q,length(entr)), col='blue', lty=2)
    idx = as.numeric(which(entr >= q))
    if (length(idx) > 0) {
      noise_spectrum = as.numeric(apply (Z1[idx, , drop = FALSE], 2, mean))
      # plot(noise_spectrum, type = 'l')
      Z1 = Z1 - noiseReduction * noise_spectrum
    }
    # re-normalize
    Z1[Z1 <= 0] = 0
  }

  if (contrast_exp != 1) {
    Z1 = Z1 ^ contrast_exp
  }

  Z1 = Z1 / max(Z1)
  if (brightness_exp != 1) {
    Z1 = Z1 / brightness_exp
  }
  if (brightness_exp < 1) {
    Z1[Z1 > 1] = 1 # otherwise values >1 are shown as white instead of black
  }

  # spectrogram of the modified fft
  if (colorTheme == 'bw') {
    color.palette = function(x) gray(seq(from = 1, to = 0, length = x))
  } else if (colorTheme == 'seewave') {
    color.palette = seewave::spectro.colors
  } else {
    colFun = match.fun(colorTheme)
    color.palette = function(x) rev(colFun(x))
  }

  if (plot) {
    op = par(c('mar', 'xaxt', 'yaxt', 'mfrow')) # save user's original pars
    if (osc) {
      layout(matrix(c(2, 1), nrow = 2, byrow = TRUE), heights = c(3, 1))
      par(mar = c(5.1, 4.1, 0, 2.1), xaxt = 's', yaxt = 'n')
      plot(seq(1, duration * 1000, length.out = length(sound)), sound,
           type = "l", xaxs = "i", yaxs = "i", xlab = xlab, ylab = '')
      axis(side = 1, labels = TRUE)
      abline(h = 0, lty = 2)
      par(mar = c(0, 4.1, 2.1, 2.1), xaxt = 'n', yaxt = 's')
      xlab = ''
    }
    seewave::filled.contour.modif2(x = X, y = Y, z = Z1, levels = seq(0, 1, length = 30),
                                   color.palette = color.palette, ylim = ylim, xlab = xlab, ...)
    # restore original pars
    par('mar' = op$mar, 'xaxt' = op$xaxt, 'yaxt' = op$yaxt, 'mfrow' = op$mfrow)
  }

  if (output == 'original') {
    return (t(Z))  # before denoising
  } else if (output == 'processed') {
    return (t(Z1))  # denoised spectrum / spectralDerivative
  }
}


#' Fourier transform windows (seewave)
#'
#' Internal soundgen function
#'
#' Generates different Fourier Transform windows. Just like
#' \code{\link[seewave]{ftwindow}}, but with the addition of a gaussian window.
#' @param wl window length, in points
#' @param wn window type (defaults to gaussian)
#' @keywords internal
ftwindow_modif = function (wl, wn = "gaussian") {
  if (wn == "bartlett")
    w = seewave::bartlett.w(wl)
  if (wn == "blackman")
    w = seewave::blackman.w(wl)
  if (wn == "flattop")
    w = seewave::flattop.w(wl)
  if (wn == "hamming")
    w = seewave::hamming.w(wl)
  if (wn == "hanning")
    w = seewave::hanning.w(wl)
  if (wn == "rectangle")
    w = seewave::rectangle.w(wl)
  if (wn == "gaussian")
    w = gaussian.w(wl)
  return(w)
}

#' Gaussian window
#'
#' Internal soundgen function.
#'
#' Generates a gaussian window of length n. Based on the formula by P. Boersma (PRAAT)
#' @param n window length, in points
#' @keywords internal
gaussian.w = function(n) {
  if (n == 0)
    stop("'n' must be a positive integer")
  w = (exp(-12 * (((1:n) / n) - 0.5) ^ 2) - exp(-12)) / (1 - exp(-12))
  # Boersma (PRAAT)
  return(w)
}

#' Frame bank
#'
#' Internal soundgen function.
#'
#' A subroutine of \code{\link{spec}} that saves windowed (and optionally
#' zero-padded) frames, i.e. chunks of the sound file of the right size and
#' spacing. Handy for further processing.
#' @param sound numeric vector
#' @inheritParams spectrogram
#' @param windowLength_points length of fft window (points)
#' @param filter fft window filter (defaults to NULL)
#' @return A matrix with \code{nrow = windowLength_points/2} and \code{ncol}
#'   depending on \code{length(sound)} and \code{step}
#' @keywords internal
#' @examples
#' a = soundgen:::getFrameBank(sin(1:1000), 16000, 512, 'gaussian', 15, 0)
getFrameBank = function(sound,
                        samplingRate,
                        windowLength_points,
                        wn,
                        step,
                        zp,
                        filter = NULL) {
  # # normalize to range from no less than -1 to no more than +1
  if (min(sound) > 0) {
    sound = scale(sound)
  }
  sound = sound / max(abs(max(sound)), abs(min(sound)))
  duration = length(sound) / samplingRate
  myseq = seq(1, max(1, (length(sound) - windowLength_points)),
              step / 1000 * samplingRate)
  if (is.null(filter)) {
    filter = ftwindow_modif(wl = windowLength_points, wn = wn)
  }
  zpExtra = floor((zp - windowLength_points) / 2) * 2 # how many extra zeroes
  # we pad with. Made even
  if (zpExtra > 0) {
    frameBank = apply(as.matrix(myseq), 1, function(x) {
      c(rep(0, zpExtra / 2),
        sound[x:(windowLength_points + x - 1)] * filter,
        rep(0, zpExtra / 2))
    })
  } else {
    frameBank = apply(as.matrix(myseq), 1, function(x) {
      sound[x:(windowLength_points + x - 1)] * filter
    })
  }
  return(frameBank)
}
