% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/segment.R
\name{segment}
\alias{segment}
\title{Segment a sound}
\usage{
segment(x, samplingRate = NULL, windowLength = 40, overlap = 80,
  shortestSyl = 40, shortestPause = 40, sylThres = 0.9,
  interburst = NULL, interburstMult = 1, burstThres = 0.075,
  peakToTrough = 3, troughLeft = TRUE, troughRight = FALSE,
  summary = FALSE, plot = FALSE, savePath = NA, ...)
}
\arguments{
\item{x}{path to a .wav file or a vector of amplitudes with specified
samplingRate}

\item{samplingRate}{sampling rate of \code{x} (only needed if \code{x} is a
numeric vector, rather than a .wav file)}

\item{windowLength, overlap}{length (ms) and overlap (%) of the smoothing
window used to produce the amplitude envelope, see
\code{\link[seewave]{env}}}

\item{shortestSyl}{minimum acceptable length of syllables, ms}

\item{shortestPause}{minimum acceptable break between syllables, ms.
Syllables separated by less time are merged. To avoid merging, specify
\code{shortestPause = NA}}

\item{sylThres}{amplitude threshold for syllable detection (as a
proportion of global mean amplitude of smoothed envelope)}

\item{interburst}{minimum time between two consecutive bursts (ms). If
specified, it overrides \code{interburstMult}}

\item{interburstMult}{multiplier of the default minimum interburst
interval (median syllable length or, if no syllables are detected, the same
number as \code{shortestSyl}). Only used if \code{interburst} is
not specified. Larger values improve detection of unusually broad shallow
peaks, while smaller values improve the detection of sharp narrow peaks}

\item{burstThres}{to qualify as a burst, a local maximum has to be at least
\code{burstThres} times the height of the global maximum of amplitude
envelope}

\item{peakToTrough}{to qualify as a burst, a local maximum has to be at
least \code{peakToTrough} times the local minimum on the LEFT over
analysis window (which is controlled by \code{interburst} or
\code{interburstMult})}

\item{troughLeft, troughRight}{should local maxima be compared to the trough
on the left and/or right of it? Default to TRUE and FALSE, respectively}

\item{summary}{if TRUE, returns only a summary of the number and spacing of
syllables and vocal bursts. If FALSE, returns a list containing full stats
on each syllable and bursts (location, duration, amplitude, ...)}

\item{plot}{if TRUE, produces a segmentation plot}

\item{savePath}{full path to the folder in which to save the plots. Defaults
to NA}

\item{...}{other graphical parameters passed to \code{\link[graphics]{plot}}}
}
\value{
If \code{summary = TRUE}, returns only a summary of the number and
  spacing of syllables and vocal bursts. If \code{summary = FALSE}, returns a
  list containing full stats on each syllable and bursts (location, duration,
  amplitude, ...).
}
\description{
Finds syllables and bursts. Syllables are defined as continuous segments with
amplitude above threshold. Bursts are defined as local maxima in amplitude
envelope that are high enough both in absolute terms (relative to the global
maximum) and with respect to the surrounding region (relative to local
mimima). See the vignette on acoustic analysis for details.
}
\details{
The algorithm is very flexible, but the parameters may be hard to optimize by
hand. If you have an annotated sample of the sort of audio you are planning
to analyze, with syllables and/or bursts counted manually, you can use it for
automatic optimization of control parameters (see
\code{\link{optimizePars}}. The defaults are the results of just such
optimization against 260 human vocalizations in Anikin, A. & Persson, T.
(2017). Non-linguistic vocalizations from online amateur videos for emotion
research: a validated corpus. Behavior Research Methods, 49(2): 758-771.
}
\examples{
sound = soundgen(nSyl = 8, sylLen = 50, pauseLen = 70,
  pitchAnchors = list(time = c(0, 1), value = c(368, 284)), temperature = 0.1,
  noiseAnchors = list(time = c(0, 67, 86, 186), value = c(-45, -47, -89, -120)),
  rolloff_noise = -8, amplAnchorsGlobal = list(time = c(0, 1), value = c(120, 20)))
spectrogram(sound, samplingRate = 16000, osc = TRUE)
 # playme(sound, samplingRate = 16000)

s = segment(sound, samplingRate = 16000, plot = TRUE)
# accept quicker and quieter syllables
s = segment(sound, samplingRate = 16000, plot = TRUE,
  shortestSyl = 25, shortestPause = 25, sylThres = .6)
# look for narrower, sharper bursts
s = segment(sound, samplingRate = 16000, plot = TRUE,
  shortestSyl = 25, shortestPause = 25, sylThres = .6,
  interburstMult = 1)

# just a summary
segment(sound, samplingRate = 16000, summary = TRUE)
}
