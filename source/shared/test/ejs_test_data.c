#include "ejs_test_data.h"

/*
 * A reduced, deterministic player-shaped fixture for yt-dlp-ejs 0.8.0. It
 * preserves the structures that EJS recognizes while keeping the embedded
 * cross-platform self-test small. The transformations deliberately remain
 * simple so the expected values can be reviewed without running JavaScript.
 */
const char retro_dlp_ejs_player_fixture[] =
    "(function(){"
    "X=function(a,b,c){"
    "var d={s:c,n:null};"
    "var e={transform:function(){"
    "if(d.s)d.s=d.s.split('')"
    ".reverse().join('');"
    "if(d.n)d.n=d.n+'-n'"
    "}};"
    "var f=Object.create(e);"
    "f.set=function(k,v){d[k]=v};"
    "f.get=function(k){return d[k]};"
    "f.clone=function(){return f};"
    "f.set('alr','yes');"
    "return f"
    "};"
    "}).call(this);";
