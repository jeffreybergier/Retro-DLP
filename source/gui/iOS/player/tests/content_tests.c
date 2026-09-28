#include "../RDLPPlayerContent.h"
#include <assert.h>
#include <stdio.h>

int main(void) {
  assert(!RDLPPlayerContentIsLong(60));
  assert(!RDLPPlayerContentIsLong(480));
  assert(RDLPPlayerContentIsLong(480.001));
  assert(!RDLPPlayerContentIsLong(NAN));
  assert(!RDLPPlayerContentIsLong(INFINITY));
  assert(!RDLPPlayerContentIsLong(0));
  assert(RDLPPlayerResumePosition(25,60)==0);
  assert(RDLPPlayerResumePosition(240,480)==0);
  assert(RDLPPlayerResumePosition(240,480.001)==240);
  assert(RDLPPlayerResumePosition(60,600)==0);
  assert(RDLPPlayerResumePosition(60.1,600)==60.1);
  assert(RDLPPlayerResumePosition(539.9,600)==539.9);
  assert(RDLPPlayerResumePosition(540,600)==0);
  assert(RDLPPlayerResumePosition(240,NAN)==240);
  assert(RDLPPlayerResumePosition(240,INFINITY)==240);
  assert(RDLPPlayerResumePosition(240,0)==240);
  puts("PASS: content duration classification and resume policy");
  return 0;
}
