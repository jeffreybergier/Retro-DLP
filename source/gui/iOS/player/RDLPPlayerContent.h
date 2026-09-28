#ifndef RDLP_PLAYER_CONTENT_H
#define RDLP_PLAYER_CONTENT_H

#include <math.h>

/* Unknown/indefinite durations are not classified as long content. */
static inline int RDLPPlayerContentIsLong(double duration) {
  return isfinite(duration) && duration>8*60;
}

static inline double RDLPPlayerResumePosition(double seconds,double duration) {
  /* Preserve an existing bookmark until the duration is known. */
  if(isfinite(duration) && duration>0 &&
     (!RDLPPlayerContentIsLong(duration) || seconds<=duration*0.1 || seconds>=duration*0.9)) return 0;
  return seconds;
}

#endif
