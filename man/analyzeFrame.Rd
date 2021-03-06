% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/utilities_analyze.R
\name{analyzeFrame}
\alias{analyzeFrame}
\title{Analyze fft frame}
\usage{
analyzeFrame(frame, autoCorrelation = NULL, samplingRate = 44100,
  trackPitch = TRUE, pitchMethods = c("autocor", "cep", "spec", "dom"),
  cutFreq = 6000, domThres = 0.1, domSmooth = 220, autocorThres = 0.75,
  autocorSmooth = NULL, cepThres = 0.45, cepSmooth = 3, cepZp = 2^13,
  specThres = 0.45, specPeak = 0.8, specSinglePeakCert = 0.6,
  specSmooth = 100, specHNRslope = 0.1, specMerge = 1, pitchFloor = 75,
  pitchCeiling = 3500, nCands = 1)
}
\arguments{
\item{frame}{the real part of the spectrum of a frame, as returned by
\code{\link[stats]{fft}}}

\item{autoCorrelation}{pre-calculated autocorrelation of the input frame
(computationally more efficient than to do it here)}

\item{samplingRate}{sampling rate (Hz)}

\item{trackPitch}{if TRUE, attempt to find F0 in this frame (FALSE if entropy
is above some threshold - specified in \code{\link{analyze}})}

\item{pitchMethods}{methods of pitch estimation to consider for determining
pitch contour: 'autocor' = autocorrelation (~PRAAT), 'cep' = cepstral,
'spec' = spectral (~BaNa), 'dom' = lowest dominant frequency band}

\item{cutFreq}{(>0 to Nyquist, Hz) repeat the calculation of spectral
descriptives after discarding all info above \code{cutFreq}.
Recommended if the original sampling rate varies across different analyzed
audio files}

\item{domThres}{(0 to 1) to find the lowest dominant frequency band, we
do short-term FFT and take the lowest frequency with amplitude at least
domThres}

\item{domSmooth}{the width of smoothing interval (Hz) for finding
\code{dom}}

\item{autocorThres}{(0 to 1) separate
voicing thresholds for detecting pitch candidates with three different
methods: autocorrelation, cepstrum, and BaNa algorithm (see Details). Note
that HNR is calculated even for unvoiced frames.}

\item{autocorSmooth}{the width of smoothing interval (in bins) for
finding peaks in the autocorrelation function. Defaults to 7 for sampling
rate 44100 and smaller odd numbers for lower values of sampling rate}

\item{cepThres}{(0 to 1) separate
voicing thresholds for detecting pitch candidates with three different
methods: autocorrelation, cepstrum, and BaNa algorithm (see Details). Note
that HNR is calculated even for unvoiced frames.}

\item{cepSmooth}{the width of smoothing interval (in bins) for finding
peaks in the cepstrum. Defaults to 31 for sampling rate 44100 and smaller
odd numbers for lower values of sampling rate}

\item{cepZp}{zero-padding of the spectrum used for cepstral pitch detection
(final length of spectrum after zero-padding in points, e.g. 2 ^ 13)}

\item{specThres}{(0 to 1) separate
voicing thresholds for detecting pitch candidates with three different
methods: autocorrelation, cepstrum, and BaNa algorithm (see Details). Note
that HNR is calculated even for unvoiced frames.}

\item{specPeak}{when looking for putative harmonics in
the spectrum, the threshold for peak detection is calculated as
\code{specPeak * (1 - HNR * specHNRslope)}}

\item{specSinglePeakCert}{(0 to 1) if F0 is calculated based on a single
harmonic ratio (as opposed to several ratios converging on the same
candidate), its certainty is taken to be \code{specSinglePeakCert}}

\item{specSmooth}{the width of window for detecting peaks in the spectrum, Hz}

\item{specHNRslope}{when looking for putative harmonics in
the spectrum, the threshold for peak detection is calculated as
\code{specPeak * (1 - HNR * specHNRslope)}}

\item{specMerge}{pitch candidates within \code{specMerge} semitones are
merged with boosted certainty}

\item{pitchFloor}{absolute bounds for pitch candidates (Hz)}

\item{pitchCeiling}{absolute bounds for pitch candidates (Hz)}

\item{nCands}{maximum number of pitch candidates per method (except for
\code{dom}, which returns at most one candidate per frame), normally 1...4}
}
\value{
Returns a list with two components: $pitch_array contains pitch
  candidates for the frame, and $summaries contains other acoustic predictors
  like HNR, specSlope, etc.
}
\description{
Internal soundgen function.
}
\details{
This function performs the heavy lifting of pitch tracking and acoustic
analysis in general: it takes the spectrum of a single fft frame as input and
analyzes it.
}
\keyword{internal}
