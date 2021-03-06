# Functions for controlling the spectrum of generated sounds (rolloff and formants).

#' Control rolloff of harmonics
#'
#' Harmonics are generated as separate sine waves. But we don't want each
#' harmonic to be equally strong, so we normally specify some rolloff function
#' that describes the loss of energy in upper harmonics relative to the
#' fundamental frequency (f0). \code{\link{getRolloff}} provides flexible
#' control over this rolloff function, going beyond simple exponential decay
#' (\code{rolloff}). Use quadratic terms to modify the behavior of a few lower
#' harmonics, \code{rolloffOct} to adjust the rate of decay per
#' octave, and \code{rolloffKHz} for rolloff correction depending on
#' f0. Plot the output with different parameter values and see examples below
#' and the vignette to get a feel for how to use \code{\link{getRolloff}}
#' effectively.
#' @param pitch_per_gc a vector of f0 per glottal cycle, Hz
#' @param nHarmonics maximum number of harmonics to generate (very weak
#'   harmonics with amplitude < \code{throwaway} will be discarded)
#' @inheritParams soundgen
#' @param rolloffParabCeiling quadratic adjustment is applied only up to
#'   \code{rolloffParabCeiling}, Hz. If not NULL, it overrides
#'   \code{rolloffParabHarm}
#' @param baseline The "neutral" frequency, at which no adjustment of rolloff
#'   takes place regardless of \code{rolloffKHz}
#' @param samplingRate sampling rate (needed to stop at Nyquist frequency and
#'   for plotting purposes)
#' @param plot if TRUE, produces a plot
#' @return Returns a matrix of amplitude multiplication factors for adjusting
#'   the amplitude of harmonics relative to f0. Each row of output contains one
#'   harmonic, and each column contains one glottal cycle.
#' @export
#' @examples
#' # steady exponential rolloff of -12 dB per octave
#' rolloff = getRolloff(pitch_per_gc = 150, rolloff = -12,
#'   rolloffOct = 0, plot = TRUE)
#' # the rate of rolloff slows down with each octave
#' rolloff = getRolloff(pitch_per_gc = 150, rolloff = -12,
#'   rolloffOct = 2, plot = TRUE)
#' # the rate of rolloff increases with each octave
#' rolloff = getRolloff(pitch_per_gc = 150, rolloff = -12,
#'   rolloffOct = -2, plot = TRUE)
#'
#' # variable f0: the lower f0, the more harmonics are non-zero
#' rolloff = getRolloff(pitch_per_gc = c(150, 800, 3000),
#'   rolloffOct = 0, plot = TRUE)
#' # without the correction for f0 (rolloffKHz),
#'   # high-pitched sounds have the same rolloff as low-pitched sounds,
#'   # producing unnaturally strong high-frequency harmonics
#' rolloff = getRolloff(pitch_per_gc = c(150, 800, 3000),
#'   rolloffOct = 0, rolloffKHz = 0, plot = TRUE)
#'
#' # parabolic adjustment of lower harmonics
#' rolloff = getRolloff(pitch_per_gc = 350, rolloffParab = 0,
#'   rolloffParabHarm = 2, plot = TRUE)
#' # rolloffParabHarm = 1 affects only f0
#' rolloff = getRolloff(pitch_per_gc = 150, rolloffParab = 30,
#'   rolloffParabHarm = 1, plot = TRUE)
#' # rolloffParabHarm=2 or 3 affects only h1
#' rolloff = getRolloff(pitch_per_gc = 150, rolloffParab = 30,
#'   rolloffParabHarm = 2, plot = TRUE)
#' # rolloffParabHarm = 4 affects h1 and h2, etc
#' rolloff = getRolloff(pitch_per_gc = 150, rolloffParab = 30,
#'   rolloffParabHarm = 4, plot = TRUE)
#' # negative rolloffParab weakens lower harmonics
#' rolloff = getRolloff(pitch_per_gc = 150, rolloffParab = -20,
#'   rolloffParabHarm = 7, plot = TRUE)
#' # only harmonics below 2000 Hz are affected
#' rolloff = getRolloff(pitch_per_gc = c(150, 600),
#'   rolloffParab = -20, rolloffParabCeiling = 2000,
#'   plot = TRUE)
#'
#' # dynamic rolloff (varies over time)
#' rolloff = getRolloff(pitch_per_gc = c(150, 250),
#'                      rolloff = c(-12, -18, -24), plot = TRUE)
#' rolloff = getRolloff(pitch_per_gc = c(150, 250), rolloffParab = 40,
#'                     rolloffParabHarm = 1:5, plot = TRUE)
#' \dontrun{
#' # only rolloff for the first glottal cycle is plotted, but the sound varies:
#' s1 = soundgen(sylLen = 1000, pitchAnchors = 250,
#'               rolloff = c(-12, -24, -2), plot = TRUE)
#' s2 = soundgen(sylLen = 1000, pitchAnchors = 250,
#'              rolloffParab = 20, rolloffParabHarm = 1:15, plot = TRUE)
#' }
getRolloff = function(pitch_per_gc = c(440),
                      nHarmonics = 100,
                      rolloff = -6,
                      rolloffOct = -3,
                      rolloffParab = 0,
                      rolloffParabHarm = 3,
                      rolloffParabCeiling = NULL,
                      rolloffKHz = -3,
                      baseline = 200,
                      throwaway = -120,
                      samplingRate = 16000,
                      plot = FALSE) {
  ## In case rolloff pars are dynamic, make them the same length as pitch_per-gc
  nGC = length(pitch_per_gc)
  update_pars = c('rolloff', 'rolloffOct', 'rolloffParab',
                  'rolloffParabHarm', 'rolloffParabCeiling', 'rolloffKHz')
  max_length = max(sapply(update_pars, function(x) length(get(x))))
  if (max_length > nGC) {
    pitch_per_gc = spline(pitch_per_gc, n = max_length)$y
    nGC = length(pitch_per_gc)
  }
  for (p in update_pars) {
    old = get(p)
    if (length(old) > 1 && length(old) != nGC) {
      new = spline(old, n = nGC)$y
      assign(p, new)
    }
  }
  rolloffParabHarm = round(rolloffParabHarm)

  ## Exponential decay
  deltas = matrix(0, nrow = nHarmonics, ncol = nGC)
  if (sum(rolloffOct != 0) > 0) {
    for (h in 2:nHarmonics) {
      deltas[h, ] = rolloffOct * (pitch_per_gc * h - baseline) / 1000
      # rolloff changes by rolloffOct per octave for each octave above H2
    }
  }
  # plot(deltas[, 1])

  r = matrix(0, nrow = nHarmonics, ncol = nGC)
  for (h in 1:nHarmonics) {
    r[h, ] = ((rolloff + rolloffKHz *
               (pitch_per_gc - baseline) / 1000) * log2(h)) + deltas[h,]
    # note that rolloff is here adjusted as a linear function of
    #   the difference between current f0 and baseline
    r[h, which(h * pitch_per_gc >= samplingRate / 2)] = -Inf # to avoid
    # aliasing, we discard all harmonics above Nyquist frequency
  }

  ## QUADRATIC term affecting the first rolloffParabHarm harmonics only
  if (any(rolloffParab != 0)) {
    if (!is.null(rolloffParabCeiling)) {
      rolloffParabHarm = round(rolloffParabCeiling / pitch_per_gc)  # vector of
      # length pitch_per_gc specifying the number of harmonics whose amplitude
      # is to be adjusted
    } else if (length(rolloffParabHarm) < ncol(r)) {
      rolloffParabHarm = rep(rolloffParabHarm, ncol(r))
      # if the original length was >1, it was upsampled at the beginning of fun
    }
    rolloffParabHarm[rolloffParabHarm == 2] = 3 # will have the effect of boosting
    # H1 (2 * F0)
    # parabola ax^2+bx+c
    # 0 at h=1 and at h=rolloffParabHarm; a parabola up/down in between. We have the following constraints on the parabola: f(1)=0; f(rolloffParabHarm)=0; f'((1+rolloffParabHarm)/2)=0; and f((1+rolloffParabHarm)/2)=rolloffParab.
    ## Solving for a,b,c
    # f'(middle) = 2a*(1+rolloffParabHarm)/2+b = a*(1+rolloffParabHarm)+b = 0, so b = -a*(1+rolloffParabHarm).
    # f(1) = a+b+c = 0, so c = -a+a*(1+rolloffParabHarm) = a*rolloffParabHarm.
    # f(middle)=rolloffParab. middle is (1+rolloffParabHarm)/2, and f( (1+rolloffParabHarm)/2 ) = a*(1+rolloffParabHarm)^2/4 + b*(1+rolloffParabHarm)/2 + c = (substituting above expressions for b and c) = a*(1+rolloffParabHarm)^2/4 - a*(1+rolloffParabHarm)*(1+rolloffParabHarm)/2 + a*rolloffParabHarm = -a*(1+rolloffParabHarm)^2/4 + a*rolloffParabHarm = -a/4*(1 + rolloffParabHarm^2 + 2*rolloffParabHarm - 4*rolloffParabHarm) = -a/4*(1-rolloffParabHarm)^2. And we want this to equal rolloffParab. Solving for a, we have a = -4*rolloffParab/(rolloffParabHarm-1)^2
    a = -4 * rolloffParab / (rolloffParabHarm - 1) ^ 2
    b = -a * (1 + rolloffParabHarm)
    c = a * rolloffParabHarm
    # # verify:
    # myf = function(s, a, b, c) {return(a * s^2 + b * s + c)}
    # s = seq(1, rolloffParabHarm[1], by = .5)
    # plot (s, myf(s, a, b, c))

    # for a single affected harmonic, just change the amplitude of F0
    r[1, which(rolloffParabHarm < 3)] =
      r[1, which(rolloffParabHarm < 3)] + rolloffParab
    # if at least 2 harmonics are to be adjusted, calculate a parabola
    for (i in which(rolloffParabHarm >= 3)) {
      rowIdx = 1:rolloffParabHarm[i]
      r[rowIdx, i] = r[rowIdx, i] + a[i] * rowIdx ^ 2 +
        b[i] * rowIdx + c[i]   # plot (r[, 1])
    }
  }

  # set values under throwaway to zero
  if (is.numeric(throwaway)) {
    # if not null and not NA
    r[r < throwaway] = -Inf
  }

  # normalize so the amplitude of F0 is always 0
  r = apply(r, 2, function(x) x - max(x))

  # plotting
  if (plot) {
    x_max = samplingRate / 2 / 1000
    if (nGC == 1 | var(pitch_per_gc) == 0) {
      idx = which(r[, 1] > -Inf)
      plot ( idx * pitch_per_gc[1] / 1000, r[idx, 1],
             type = 'b', xlim = c(0, x_max), xlab = 'Frequency, Hz',
             ylab = 'Amplitude, dB', main = 'Glottal source rolloff')
    } else {
      pitch_min = min(pitch_per_gc)
      pitch_max = max(pitch_per_gc)
      idx_min = which.min(pitch_per_gc)
      idx_max = which.max(pitch_per_gc)
      rows_min = 1:tail(which(r[, idx_min] > -Inf), 1)
      rows_max = 1:tail(which(r[, idx_max] > -Inf), 1)
      freqs_min = rows_min * pitch_min / 1000
      freqs_max = rows_max * pitch_max / 1000
      rolloff_min = r[rows_min, idx_min]
      rolloff_max = r[rows_max, idx_max]
      plot(freqs_min, rolloff_min, type = 'b', col = 'blue',
           xlim = c(0, x_max), xlab = 'Frequency, Hz',
           ylab = 'Amplitude, dB', main = 'Glottal source rolloff')
      text(x = x_max, y = -10, labels = 'Lowest pitch',
           col = 'blue', pos = 2)
      points(freqs_max, rolloff_max, type = 'b', col = 'red')
      text(x = x_max, y = 0, labels = 'Highest pitch',
           col = 'red', pos = 2)
    }
  }

  # convert from dB to linear amplitude multipliers
  r = 10 ^ (r / 20)

  # shorten by discarding harmonics that are 0 throughout the sound
  r = r[which(apply(r, 1, sum) > 0), , drop = FALSE]
  rownames(r) = 1:nrow(r) # helpful for adding vocal fry

  return (r)
}
