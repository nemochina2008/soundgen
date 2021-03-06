#' Spectral envelope
#'
#' Prepares a spectral envelope for filtering a sound to add formants, lip
#' radiation, and some stochastic component regulated by temperature.
#' Formants are specified as a list containing time, frequency, amplitude,
#' and width values for each formant (see examples). NB: each formant is
#' generated as a gamma distribution with mean = freq and SD = width. Formant
#' bandwidths in soundgen are therefore NOT compatible with formant bandwidths
#' used in Klatt synthesizer and other algorithms that rely on FIR instead of
#' FFT.
#' @param nr the number of frequency bins = windowLength_points/2, where
#'   windowLength_points is the size of window for Fourier transform
#' @param nc the number of time steps for Fourier transform
#' @inheritParams soundgen
#' @param formants a character string like "aaui" referring to default presets
#'   for speaker "M1"; a vector of formant frequencies; or a list of formant
#'   times, frequencies, amplitudes, and bandwidths, with a single value of each
#'   for static or multiple values of each for moving formants. \code{formants =
#'   NA} defaults to schwa. Time stamps for formants and mouthOpening can be
#'   specified in ms or an any other arbitrary scale.
#' @param formDrift scale factor regulating the effect of temperature on the
#'   depth of random drift of all formants (user-defined and stochastic): the
#'   higher, the more formants drift at a given temperature
#' @param formDisp scale factor regulating the effect of temperature on the
#'   irregularity of the dispersion of stochastic formants: the higher, the more
#'   unevenly stochastic formants are spaced at a given temperature
#' @param speedSound speed of sound in warm air, cm/s. Stevens (2000) "Acoustic
#'   phonetics", p. 138
#' @param openMouthBoost amplify the voice when the mouth is open by
#'   \code{openMouthBoost} dB
#' @param formantDepStoch the amplitude of additional formants added above
#'   the highest specified formant (only if temperature > 0)
#' @param smoothLinearFactor regulates smoothing of formant anchors (0 to +Inf)
#'   as they are upsampled to the number of fft steps \code{nc}. This is
#'   necessary because the input \code{formants} normally contains fewer
#'   sets of formant values than the number of fft steps.
#'   \code{smoothLinearFactor} = 0: close to default spline; >3: approaches
#'   linear extrapolation
#' @param plot if TRUE, produces a plot of the spectral envelope
#' @param duration duration of the sound, ms (for plotting purposes only)
#' @param colorTheme black and white ('bw'), as in seewave package ('seewave'),
#'   or another color theme (e.g. 'heat.colors')
#' @param nCols number of colors in the palette
#' @param xlab,ylab labels of axes
#' @param ... other graphical parameters passed on to \code{image()}
#' @export
#' @return Returns a spectral filter (matrix nr x nc, where nr is the number of
#'   frequency bins = windowLength_points/2 and nc is the number of time steps)
#' @examples
#' # [a] with F1-F3 visible
#' e = getSpectralEnvelope(nr = 512, nc = 50,
#'   formants = soundgen:::convertStringToFormants('a'),
#'   temperature = 0, plot = TRUE)
#' # image(t(e))  # to plot the output on a linear scale instead of dB
#'
#' # some "wiggling" of specified formants plus extra formants on top
#' e = getSpectralEnvelope(nr = 512, nc = 50,
#'   formants = soundgen:::convertStringToFormants('a'),
#'   temperature = 0.1, formantDepStoch = 20, plot = TRUE)
#' # a schwa based on the length of vocal tract = 15.5 cm
#' e = getSpectralEnvelope(nr = 512, nc = 50, formants = NA,
#'   temperature = .1, vocalTract = 15.5, plot = TRUE)
#'
#' # no formants at all, only lip radiation
#' e = getSpectralEnvelope(nr = 512, nc = 50,
#'   formants = NA, temperature = 0, plot = TRUE)
#'
#' # mouth opening
#' e = getSpectralEnvelope(nr = 512, nc = 50,
#'   vocalTract = 16, plot = TRUE, lipRad = 6, noseRad = 4,
#'   mouthAnchors = data.frame(time = c(0, .5, 1), value = c(0, 0, .5)))
#'
#' # manual specification of formants
#' e = getSpectralEnvelope(nr = 512, nc = 50, plot = TRUE, samplingRate = 16000,
#'   formants = list(f1 = data.frame(time = c(0, 1), freq = c(900, 500),
#'                                   amp = 20, width = c(80, 50)),
#'                   f2 = data.frame(time = c(0, 1), freq = c(1200, 2500),
#'                                   amp = 20, width = 100),
#'                   f3 = data.frame(time = 0, freq = 2900,
#'                                   amp = 20, width = 120)))
getSpectralEnvelope = function(nr,
                               nc,
                               formants = NA,
                               formantDep = 1,
                               lipRad = 6,
                               noseRad = 4,
                               mouthAnchors = NA,
                               mouthOpenThres = 0.2,
                               openMouthBoost = 0,
                               vocalTract = NULL,
                               temperature = 0.05,
                               formDrift = .3,
                               formDisp = .2,
                               formantDepStoch = 20,
                               smoothLinearFactor = 1,
                               samplingRate = 16000,
                               speedSound = 35400,
                               plot = FALSE,
                               duration = NULL,
                               colorTheme = c('bw', 'seewave', '...')[1],
                               nCols = 100,
                               xlab = 'Time',
                               ylab = 'Frequency, kHz',
                               ...) {
  # standard formatting
  formants = reformatFormants(formants)

  ## estimate vocal tract length
  if (!is.numeric(vocalTract) && is.list(formants)) {
    # if we don't know vocalTract, but at least one formant is defined,
    # we guess the length of vocal tract
    vocalTract = estimateVTL(formants = formants,
                             speedSound = speedSound,
                             checkFormat = FALSE)  # already checked
  }

  # if is.na(formants) or if there's something wrong with it,
  # we fall back on vocalTract to make a schwa
  if (length(formants[[1]]) < 2 & is.numeric(vocalTract) &
      temperature > 0 & formantDep > 0 & formantDepStoch > 0) {
    freq = speedSound / 4 / vocalTract
    formants = list('f1' = data.frame(
      'time' = 0,
      'freq' = freq,
      'amp' = NA,
      'width' = getBandwidth(freq)  # corrected Tappert, Martony, and Fant (TMF)-1963
    ))
  }

  # if there are zeros, set all NA amps to formantDepStoch
  if (is.list(formants)) {
    any_zeros = any(sapply(formants, function(f) {
      # check if there are any negative amp values, excluding NA's
      a = f$amp
      any(is.numeric(a)) && any(a < 0, na.rm = TRUE)
    }))
    if (any_zeros) {
      for (f in 1:length(formants)) {
        if (!is.numeric(formants[[f]]$amp)) {
          formants[[f]]$amp = formantDepStoch
        }
      }
    }
  }

  # create a "spectrogram"-shaped filter matrix
  spectralEnvelope = matrix(0, nrow = nr, ncol = nc)

  ### START OF FORMANTS
  if (is.list(formants)) {
    # upsample to the length of fft steps
    nPoints = max(unlist(lapply(formants, nrow)))
    formants_upsampled = lapply(formants, function(f) {
      temp = apply(f, 2, function(y) {
        if (length(y) > 1 & !any(is.na(y))) {
          # just spline produces imprecise, overly smoothed curves. Loess is just
          # too slow for this. So we apply linear extrapolation to formant values
          # first, to get a fairly straight line between anchors, and THEN smooth
          # it out with spline
          out = spline(approx(y, n = nPoints + 2 ^ smoothLinearFactor,
                              x = f$time)$y, n = nc)$y
        } else {
          out = rep(y[1], nc)
        }
        out
      })
      if (!is.matrix(temp)) {
        # if nc==1, we get numeric instead of matrix and need to convert
        temp = t(as.matrix(temp))
      }
      temp
    }) # check that class(formants_upsampled[[1]]) == 'matrix'

    ## Stochastic part (only for temperature > 0)
    if (temperature > 0) {
      # non-integer formants like "f1.4" refer to extra zero-pole pairs.
      # They should not be considered for VTL estimation or for adding formants
      non_integer_formants = apply(as.matrix(names(formants_upsampled)),
                                   1,
                                   function(x) {
                                     grepl('.', x, fixed = TRUE)
                                   })
      # create a few new, relatively high-frequency extra formants
      if (!is.numeric(vocalTract) && length(formants) > 1) {
        ff = unlist(lapply(formants[!non_integer_formants], function(x) x$freq[1]))
        formantDispersion = getFormantDispersion(ff,
                                                 speedSound = speedSound,
                                                 method = 'accurate')
      } else if (is.numeric(vocalTract)) {
        formantDispersion = speedSound / (2 * vocalTract)
      } else {
        formantDispersion = NA # making sdG also NA, ie extra formants not added
      }
      sdG = formantDispersion * temperature * formDisp
      nFormants = length(formants_upsampled)
      nFormants_integer = length(formants_upsampled) - sum(non_integer_formants)
      freq_max = max(formants_upsampled[[nFormants]][, 'freq'])

      if (!is.na(sdG) && formantDepStoch > 0) {
        # formant_f = (2 * f - 1) / 2 * formantDispersion,
        # therefore, to generate formants to 2 * Nyquist
        # (to compensate for downward drag of lower formants)
        # 2 * nyquist = (2 * nExtraFormants - 1) / 2 * formantDispersion
        # Solving for nExtraFormants gives (nyquist * 4 / formantDispersion + 1) / 2:
        nExtraFormants = round((samplingRate * 2 / formantDispersion + 1) / 2) - nFormants
        if (is.numeric(nExtraFormants) && nExtraFormants > 0) {
          extraFreqs_regular = (2 * ((nFormants_integer + 1):(nFormants_integer + nExtraFormants)) - 1) /
            2 * formantDispersion
          extraFreqs = rgamma(nExtraFormants,
                              extraFreqs_regular ^ 2 / sdG ^ 2,
                              extraFreqs_regular / sdG ^ 2)
          extraAmps = rgamma(
            nExtraFormants,
            (formantDep / temperature) ^ 2,
            formantDepStoch * formantDep / (formantDepStoch * temperature) ^ 2
          )
          extraWidths = getBandwidth(extraFreqs)
          for (f in 1:nExtraFormants) {
            formants_upsampled[[nFormants + 1]] = data.frame (
              'time' = formants_upsampled[[1]][, 'time'],
              'freq' = extraFreqs[f],
              'amp' = ifelse(any_zeros, extraAmps[f], NA),
              'width' = extraWidths[f]
            )
            nFormants = length(formants_upsampled)
          }
        }
      }

      # wiggle both user-specified and stochastic formants
      for (f in 1:nFormants) {
        for (c in 2:4) {
          # wiggle freq, ampl and bandwidth independently
          rw = getRandomWalk(
            len = nc,
            rw_range = temperature * formDrift,
            rw_smoothing = 0.3,
            trend = rnorm(1)
          )
          # if nc == 1, returns one number close to 1
          if (length(rw) > 1) {
            # for actual random walks, make sure mean is 1
            rw = rw - mean(rw) + 1
          }
          formants_upsampled[[f]][, c] = formants_upsampled[[f]][, c] * rw
        }
      } # end of wiggling formants
    } # end of if temperature > 0

    ## Deterministic part
    # convert formant freqs and widths from Hz to bins
    bin_width = samplingRate / 2 / nr # Hz
    bin_freqs = seq(bin_width / 2, samplingRate / 2, length.out = nr) # Hz
    for (f in 1:length(formants_upsampled)) {
      formants_upsampled[[f]][, 'freq'] =
        (formants_upsampled[[f]][, 'freq'] - bin_width / 2) / bin_width + 1
      # frequencies expressed in bin indices (how many bin widths above the
      # central frequency of the first bin)
      formants_upsampled[[f]][, 'width'] =
        formants_upsampled[[f]][, 'width'] / bin_width
    }

    # mouth opening
    if (length(mouthAnchors) < 1 | any(is.na(mouthAnchors))) {
      mouthOpening_upsampled = rep(0.5, nc) # defaults to mouth half-open the
      # whole time - sort of hanging loosely agape ;))
      mouthOpen_binary = rep(1, nc)
    } else {
      mouthOpening_upsampled = getSmoothContour(
        len = nc,
        anchors = mouthAnchors,
        valueFloor = permittedValues['mouthOpening', 'low'],
        valueCeiling = permittedValues['mouthOpening', 'high'],
        plot = FALSE
      )
      # mouthOpening_upsampled[mouthOpening_upsampled < mouthOpenThres] = 0
      mouthOpen_binary = ifelse(mouthOpening_upsampled > mouthOpenThres, 1, 0)
    }
    # plot(mouthOpening_upsampled, type = 'l')

    # adjust formants for mouth opening
    if (!is.null(vocalTract) && is.finite(vocalTract)) {
      # is.finite() returns F for NaN, NA, inf, etc
      adjustment_hz = (mouthOpening_upsampled - 0.5) * speedSound /
        (4 * vocalTract) # speedSound = 35400 cm/s, speed of sound in warm
      # air. The formula for mouth opening is adapted from Moore (2016)
      # "A Real-Time Parametric General-Purpose Mammalian Vocal Synthesiser".
      # mouthOpening = .5 gives no modification (neutral, "default" position).
      # Basically we assume a closed-closed tube for closed mouth and a
      # closed-open tube for open mouth, but since formants can be specified
      # rather than calculated based on vocalTract, we just subtract half the
      # total difference between open and closed tubes in Hz from each formant
      # value as the mouth goes from half-open (neutral) to fully closed, or we
      # add half that value as the mouth goes from neutral to max open
      adjustment_bins = (adjustment_hz - bin_width / 2) / bin_width + 1
    } else {
      adjustment_bins = 0
    }
    for (f in 1:length(formants_upsampled)) {
      formants_upsampled[[f]][, 'freq'] =
        formants_upsampled[[f]][, 'freq'] + adjustment_bins
      # force each formant frequency to be positive
      formants_upsampled[[f]][, 'freq'] [formants_upsampled[[f]][, 'freq'] < 1] = 1
    }

    # nasalize the parts with closed mouth: see Hawkins & Stevens (1985);
    # http://www.cslu.ogi.edu/tutordemos/SpectrogramReading/cse551html/cse551/node35.html
    nasalizedIdx = which(mouthOpen_binary == 0) # or specify a separate
    # increase F1 bandwidth to 175 Hz
    formants_upsampled$f1[nasalizedIdx, 'width'] = 175 / bin_width
    # nasalization contour
    if (length(nasalizedIdx) > 0) {
      # add a pole
      formants_upsampled$fnp = formants_upsampled$f1
      formants_upsampled$fnp[, 'amp'] = 0
      formants_upsampled$fnp[nasalizedIdx, 'amp'] = formantDepStoch
      formants_upsampled$fnp[nasalizedIdx, 'width'] =
        formants_upsampled$f1[nasalizedIdx, 'width'] * 2 / 3
      formants_upsampled$fnp[nasalizedIdx, 'freq'] =
        ifelse(
          formants_upsampled$f1[nasalizedIdx, 'freq'] > 550 / bin_width,
          formants_upsampled$f1[nasalizedIdx, 'freq'] - 250 / bin_width,
          formants_upsampled$f1[nasalizedIdx, 'freq'] + 250 / bin_width
        )
      # 250 Hz below or above F1, depending on whether F1 is above or below
      # 550 Hz

      # add a zero
      formants_upsampled$fnz = formants_upsampled$f1
      formants_upsampled$fnz[, 'amp'] = 0
      formants_upsampled$fnz[nasalizedIdx, 'amp'] = -formantDepStoch
      formants_upsampled$fnz[nasalizedIdx, 'freq'] =
        (formants_upsampled$fnp[nasalizedIdx, 'freq'] +
           formants_upsampled$f1[nasalizedIdx, 'freq']) / 2  # midway between
      # f1 and fnp
      formants_upsampled$fnz[nasalizedIdx, 'width'] =
        formants_upsampled$fnp[nasalizedIdx, 'width']
      # modify f1
      formants_upsampled$f1[nasalizedIdx, 'amp'] =
        formants_upsampled$f1[nasalizedIdx, 'amp'] * 4 / 5
      formants_upsampled$f1[nasalizedIdx, 'width'] =
        formants_upsampled$f1[nasalizedIdx, 'width'] * 5 / 4
    }

    # Add formants to spectrogram
    freqs_bins = 1:nr
    poles = 1:length(formants_upsampled)
    zeros = as.numeric(which(sapply(formants_upsampled, function(x) any(x[, 'amp'] < 0))))
    if (length(zeros) > 0) poles = poles[-zeros]
    s = complex(real = 0, imaginary = 2 * pi * freqs_bins)
    na_amp = sapply(formants_upsampled, function(x) is.na(x[1, 'amp']))  # check only the first frame

    if (length(zeros) == 0) {  # all-pole
      # special case for faster computing (saves ~10 to 30 ms). Stevens 2000 p. 131
      for (f in 1:length(formants_upsampled)) {
        pf = 2 * pi * formants_upsampled[[f]][, 'freq']
        bp = -formants_upsampled[[f]][, 'width'] * pi
        s1 = complex(real = bp, imaginary = pf)
        s1c = Conj(s1)
        formant = matrix(0, nrow = nr, ncol = nc)
        for (c in 1:nc) {
          # actually much faster w/o log-transform, and numbers don't get very large anyhow
          tns = s1[c] * s1c[c] / (s - s1[c]) / (s - s1c[c])
          formant[, c] = log10(abs(tns))
          if (na_amp[f]) {
            formant[, c] = formant[, c] * 20  # formantDepStoch can be 0
          } else {
            formant[, c] = formant[, c] / max(formant[, c]) * formants_upsampled[[f]][c, 'amp']
          }
          # plot(bin_freqs, formant[, c], type = 'l')
        }
        spectralEnvelope = spectralEnvelope + formant
      }
    } else {  # both zeros and poles
      # General case. Stevens 2000 p. 137
      n = length(formants_upsampled)
      freqs = matrix(sapply(formants_upsampled[1:n], function(x) x[, 'freq']), ncol = n)
      widths = matrix(sapply(formants_upsampled[1:n], function(x) x[, 'width']), ncol = n)
      amps = matrix(sapply(formants_upsampled[1:n], function(x) x[, 'amp']), ncol = n)
      amps_norm = abs(amps / 20)  # we know which ones are zeros, but their amps must be positive
      if (any(na_amp)) {
        amps_norm[is.na(amps_norm)] = formantDepStoch / 20
      }

      for (c in 1:nc) {
        # instead of looping through formants (all-pole), we loop through frames
        pf = 2 * pi * freqs[c, ]
        bp = widths[c, ] * pi
        s1 = complex(real = bp[poles], imaginary = pf[poles])
        s1c = Conj(s1)
        s0 = complex(real = bp[zeros], imaginary = pf[zeros])
        s0c = Conj(s0)
        # numerator = prod(s1 ^ amps_norm[c, poles]) * prod(s1c ^ amps_norm[c, poles])  # can exceed 10^150
        log_numerator = sum(amps_norm[c, poles] * log10(s1)) +
          sum(amps_norm[c, poles] * log10(s1c))
        if (length(zeros) > 0) {
          for (z in 1:length(zeros)) {
            # numerator = numerator * ((s - s0[z]) * (s - s0c[z])) ^ amps_norm[c, zeros[z]]
            log_numerator = log_numerator + amps_norm[c, zeros[z]] *
              log10((s - s0[z]) * (s - s0c[z]))
          }
          # denominator = prod(s0 ^ amps_norm[c, zeros]) * prod(s0c ^ amps_norm[c, zeros])
          log_denominator = sum(amps_norm[c, zeros] * log10(s0)) +
            sum(amps_norm[c, zeros] * log10(s0c))
        } else {
          # denominator = 1
          log_denominator = 0
        }
        for (p in 1:length(poles)) {
          # denominator = denominator * ((s - s1[p]) * (s - s1c[p])) ^ amps_norm[c, poles[p]]
          log_denominator = log_denominator + amps_norm[c, poles[p]] *
            log10((s - s1[p]) * (s - s1c[p]))
        }
        # tns = numerator / denominator
        log_tns = log_numerator - log_denominator
        # formants_per_bin = 20 * log10(abs(tns))
        formants_per_bin = 20 * Re(log_tns)
        # plot(bin_freqs, formants_per_bin, type = 'l')
        spectralEnvelope[, c] = spectralEnvelope[, c] + formants_per_bin
      }
    }
    spectralEnvelope = spectralEnvelope * formantDep
  } else {
    mouthOpen_binary = rep(1, nc)
    mouthOpening_upsampled = rep(0.5, nc)
  }
  # plot(spectralEnvelope[, 1], type = 'l')
  # image(t(spectralEnvelope))

  # add correction for not adding higher formants
  # rolloffAdjust = 0 - 12 * log2(((nr*1):1)) [1:nr]
  # rolloffAdjust = rolloffAdjust - min(rolloffAdjust)
  # spectralEnvelope = apply(spectralEnvelope,
  #                          2,
  #                          function(x) x + rolloffAdjust)
  # END OF FORMANTS

  # add lip radiation when the mouth is open and nose radiation when the mouth is closed
  lip_dB = lipRad * log2(1:nr) # vector of length nr
  nose_dB = noseRad * log2(1:nr)
  # plot(lip_dB, type = 'l'); plot(nose_dB, type = 'l')
  for (c in 1:nc) {
    spectralEnvelope[, c] = spectralEnvelope[, c] +
      lip_dB * mouthOpen_binary[c] +
      nose_dB * (1 - mouthOpen_binary[c]) +
      mouthOpen_binary[c] * openMouthBoost
  }

  # convert from dB to linear multiplier of power spectrum
  spectralEnvelope_lin = 10 ^ (spectralEnvelope / 20)

  if (plot) {
    if (is.numeric(duration)) {
      x = seq(0, duration, length.out = nc)
    } else {
      x = seq(0, 1, length.out = nc)
    }
    if (colorTheme == 'bw') {
      col = gray(seq(from = 1, to = 0, length = nCols))
    } else if (colorTheme == 'seewave') {
      col = seewave::spectro.colors(nCols)
    } else {
      colFun = match.fun(colorTheme)
      col = rev(colFun(nCols))
    }
    image(x = x,
          y = seq(0, samplingRate /2, length.out = nr) / 1000,
          z = t(spectralEnvelope),
          xlab = xlab,
          ylab = ylab,
          col = col,
          ...)
  }

  return(spectralEnvelope_lin)
}


#' Reformat formants
#'
#' Internal soundgen function.
#'
#' Checks that the formants are formatted in a valid way and expands them to a
#' standard list of dataframes with time, frequency, amplitude, and bandwidth of
#' each formant specified explicitly.
#' @param formants either a character string like "aoiu" or a list with an entry
#'   for each formant
#' @examples
#' formants = soundgen:::reformatFormants('aau')
#' formants = soundgen:::reformatFormants(c(500, 1500, 2500))
#' formants = soundgen:::reformatFormants(list(f1 = 500, f2 = c(1500, 1700)))
#' formants = soundgen:::reformatFormants(list(
#'      f1 = list(freq = 800, amp = 30),
#'      f2 = list(freq = c(1500, 1700, 2200), width = c(100, 150, 175))
#' ))
reformatFormants = function(formants) {
  if (class(formants) == 'character') {
    # "aui" etc - read off values from presets$M1
    formants = convertStringToFormants(formants)
  } else if (is.numeric(formants)) {
    # expand to full format from e.g. "formants = c(500, 1500, 2500)"
    freqs = formants
    formants = vector('list', length(freqs))
    names(formants) = paste0('f', 1:length(freqs))
    for (f in 1:length(freqs)) {
      formants[[f]] = data.frame(time = 0,
                                 freq = freqs[f],
                                 amp = NA,
                                 width = getBandwidth(freqs[f]))
    }
  }
  if (is.list(formants)) {
    for (f in 1:length(formants)) {
      formant = formants[[f]]
      if (is.list(formant) && 'freq' %in% names(formant)) {
        # expand to full format from e.g. f1 = list(freq = 550, amp = 30)
        formant = as.data.frame(formant)
        if (is.null(formant$time)) {
          formant$time = seq(0, 1, length.out = nrow(formant))
        }
        if (is.null(formant$amp)) {
          formant$amp = NA
        }
        if (is.null(formant$width)) {
          formant$width = getBandwidth(formant$freq)
        }
      } else if (is.numeric(formant)) {
        # expand to full format from e.g. f1 = 550
        # (numbers are assumed to represent frequency)
        formant = data.frame(time = seq(0, 1, length.out = length(formant)),
                             freq = formant,
                             amp = rep(NA, length(formant)),
                             width = getBandwidth(formant))
      }
      # make sure columns are in the right order (for esthetics & debugging)
      formants[[f]] = formant[, c('time', 'freq', 'amp', 'width')]
    }
  } else if (!is.null(formants) && !is.na(formants)) {
    stop('If defined, formants must be either a list or a string of characters
         from dictionary presets: a, o, i, e, u, 0 (schwa)')
  }
  return(formants)
}


#' Get bandwidth
#'
#' Internal soundgen function.
#'
#' Calculates formant bandwidth as a function of formant frequencies using a
#' modified version of TMF-63 formula. Namely, above 500 Hz it follows the
#' original formula from Tappert, Martony, and Fant (TMF)-1963, and below 500 Hz
#' it applies a correction to allow for energy losses at low frequencies. See
#' Khodai-Joopari & Clermont (2002), "Comparison of formulae for estimating
#' formant bandwidths".
#' @param f a vector of formant frequencies, Hz
#' @examples
#' f = 1:5000
#' plot(f, soundgen:::getBandwidth(f), type = 'l',
#'   xlab = 'Formant frequency, Hz', ylab = 'Estimated bandwidth, Hz')
getBandwidth = function(f) {
  b = rep(NA, length(f))
  f1 = which(f < 500)
  f2 = which(f >= 500)
  b[f1] =  52.08333 * (1 + (f[f1]-500) ^ 2/ 10 ^ 5)
  b[f2] = 50 * (1 + f[f2] ^ 2 / 6 / 10 ^ 6)
  # plot(f, b, type = 'l')
  return(b)
}

#' Get formant dispersion
#'
#' Internal soundgen function.
#'
#' Estimates formant dispersion based on one or more formant frequencies.
#' @param formants a vector of formant frequencies, Hz
#' @inheritParams getSpectralEnvelope
#' @param method method of calculating formant dispersion: \code{fast} for
#'   simple averaging of inter-formant difference, \code{accurate} for fitting a
#'   linear regression to formant frequencies
#' @examples
#' nIter = 100  # nIter = 10000 for better results
#' speedSound = 35400
#' out = data.frame(vtl = runif(nIter, 5, 70),
#'                  nFormants = round(runif(nIter, 1, 10)),
#'                  noise = runif(nIter, 0, .2),
#'                  vtl_est = rep(NA, nIter),
#'                  error = rep(NA, nIter))
#' for (i in 1:nIter) {
#'   a = 1:out$nFormants[i]
#'   formants = sort(speedSound * (2 * a - 1) / (4 * out$vtl[i]) * rnorm(n = length(a),
#'                                                                  mean = 1,
#'                                                                  sd = out$noise[i]))
#'   disp = soundgen:::getFormantDispersion(formants, method = 'fast')
#'   out$vtl_est[i] = speedSound / 2 / disp
#'   out$error[i] = (out$vtl[i] -  out$vtl_est[i]) / out$vtl[i]
#' }
#' \dontrun{
#' library(ggplot2)
#' ggplot(out, aes(x = nFormants, y = error)) +
#'   geom_point(alpha = .1) +
#'   geom_smooth() +
#'   theme_bw()
#' ggplot(out, aes(x = noise, y = error)) +
#'   geom_point(alpha = .1) +
#'   geom_smooth() +
#'   theme_bw()
#' }
getFormantDispersion = function(formants,
                                speedSound = 35400,
                                method = c('fast', 'accurate')[2]) {
  if (!is.numeric(formants) | length(formants) < 1) return(NA)
  if (method == 'fast') {
    l = length(formants)
    if (l > 1) {
      formantDispersion = mean(diff(formants))
    } else {
      formantDispersion = 2 * formants
    }
  } else if (method == 'accurate') {
    # Reby et al. (2005) "Red deer stags use formants..."
    deltaF = (2 * (1:length(formants)) - 1) / 2
    # plot(deltaF, formants)
    mod = lm(formants ~ deltaF - 1)  # NB: no intercept, i.e. forced to pass through 0
    formantDispersion = summary(mod)$coef[1]
  }
  return(formantDispersion)
}


#' Prepare a list of formants
#'
#' Internal soundgen function.
#'
#' Takes a string of phonemes entered WITHOUT ANY BREAKS. Recognized phonemes in
#' the human preset dictionary: vowels "a" "o" "i" "e" "u" "0" (schwa);
#' consonants "s" "x" "j".
#' @param phonemeString a string of characters from the dictionary of phoneme
#'   presets, e.g., uaaaaii (short u - longer a - medium-long i)
#' @param speaker name of the preset dictionary to use
#' @return Returns a list of formant values, which can be fed directly into
#'   \code{\link{getSpectralEnvelope}}
#' @keywords internal
#' @examples
#' formants = soundgen:::convertStringToFormants(phonemeString = 'a')
#' formants = soundgen:::convertStringToFormants(
#'   phonemeString = 'au', speaker = 'M1')
#' formants = soundgen:::convertStringToFormants(
#'   phonemeString = 'aeui', speaker = 'F1')
#' formants = soundgen:::convertStringToFormants(
#'   phonemeString = 'aaeuiiiii', speaker = 'Chimpanzee')
convertStringToFormants = function(phonemeString, speaker = 'M1') {
  availablePresets = names(presets[[speaker]]$Formants$vowels)
  if (length(availablePresets) < 1) {
    warning(paste0('No phoneme presets found for speaker ', speaker,
                   '. Defaulting to M1'))
    speaker = 'M1'
    availablePresets = names(presets[[speaker]]$Formants$vowels)
  }
  input_phonemes = strsplit(phonemeString, "")[[1]]
  valid_phonemes = input_phonemes[input_phonemes %in% availablePresets]
  unique_phonemes = unique(valid_phonemes)
  if (length(valid_phonemes) < 1)
    return(NA)

  # for each input vowel, look up the corresponding formant values
  # in the presets dictionary and append to formants
  vowels = list()
  formantNames = character()
  for (v in 1:length(unique_phonemes)) {
    vowels[[v]] = presets[[speaker]]$Formants$vowels[unique_phonemes[v]][[1]]
    formantNames = c(formantNames, names(vowels[[v]]))
  }
  formantNames = sort(unique(formantNames))
  names(vowels) = unique_phonemes

  # make sure we have filled in info on all formants from the entire
  # sequence of vowels for each individual vowel
  for (v in 1:length(vowels)) {
    absentFormants = formantNames[!formantNames %in% names(vowels[[v]])]
    for (f in absentFormants) {
      closestFreq = unlist(sapply(vowels, function(x) x[f]))
      # names_stripped = substr(names(closestFreq),
      #                         nchar(names(closestFreq)) - 3,
      #                         nchar(names(closestFreq)))
      # closestFreq = closestFreq[which(names_stripped == 'freq')]
      vowels[[v]] [[f]] = as.numeric(na.omit(closestFreq))[1]
      # NB: instead of the last [1], ideally we should specify some intelligent
      # way to pick up the closest vowel with this missing formant, not just the
      # first one, but that's only a problem in long sequences of vowels with
      # really different numbers of formants (nasalization)
    }
  }

  # initialize a common list of exact formants
  formants = vector("list", length(formantNames))
  names(formants) = formantNames

  # for each vowel, append its formants to the common list
  for (v in 1:length(valid_phonemes)) {
    vowel = vowels[[valid_phonemes[v]]]
    for (f in 1:length(vowel)) {
      formantName = names(vowel)[f]
      formants[[formantName]] = c(formants[[formantName]], vowel[[f]])
    }
  }

  return (formants)
}

#' Estimate vocal tract length
#'
#' Estimates the length of vocal tract based on formant frequencies, assuming
#' that the vocal tract can be modeled as a tube open as both ends.
#' @inheritParams getSpectralEnvelope
#' @param formants a character string like "aaui" referring to default presets
#'   for speaker "M1"; a vector of formant frequencies; or a list of formant
#'   times, frequencies, amplitudes, and bandwidths, with a single value of each
#'   for static or multiple values of each for moving formants.
#' @param checkFormat if TRUE, expands shorthand format specifications into the
#'   canonical form of a list with four components: time, frequency, amplitude
#'   and bandwidth for each format (as returned by the internal function
#'   \code{reformatFormants})
#' @return Returns the estimated vocal tract length in cm.
#' @export
#' @examples
#' estimateVTL(NA)
#' estimateVTL(500)
#' estimateVTL(c(600, 1850, 3100))
#' estimateVTL(formants = list(f1 = 600, f2 = 1650, f3 = 2400))
#'
#' # for moving formants, frequencies are averaged over time,
#' # i.e. this is identical to the previous example
#' estimateVTL(formants = list(f1 = c(500, 700), f2 = 1650, f3 = c(2200, 2600)))
estimateVTL = function(formants, speedSound = 35400, checkFormat = TRUE) {
  if (checkFormat) {
    formants = reformatFormants(formants)
  }
  if (is.list(formants) && is.numeric(formants[[1]]$freq)) {
    # if we don't know vocalTract, but at least one formant is defined,
    # we guess the length of vocal tract
    formant_freqs = unlist(sapply(formants, function(f) mean(f$freq)))
    non_integer_formants = apply(as.matrix(names(formant_freqs)),
                                 1,
                                 function(x) {
                                   grepl('.', x, fixed = TRUE)
                                 })
    formant_freqs = formant_freqs[!non_integer_formants]
    formantDispersion = getFormantDispersion(formant_freqs,
                                             speedSound = speedSound,
                                             method = 'accurate')
    vocalTract = ifelse(
      is.numeric(formantDispersion),
      speedSound / 2 / formantDispersion,
      speedSound / 4 / formants$f1$freq
    )
  } else {
    vocalTract = NA
  }
  return(vocalTract)
}
