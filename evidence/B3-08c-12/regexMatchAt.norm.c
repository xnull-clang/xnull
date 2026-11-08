int xn_regexMatchAt(rt_string * xn_p_pattern, int64_t xn_p_pi, rt_string * xn_p_text, int64_t xn_p_ti) {
size_t xn_tN = xn_root_mark();
xn_root_add(xn_p_pattern);
xn_root_add(xn_p_text);
#line 306 "tests/b3/fixtures/bundle_text/app.x"
int64_t plen = xn_str_length(xn_p_pattern);
#line 307 "tests/b3/fixtures/bundle_text/app.x"
if (((xn_p_pi >= plen))) {
size_t xn_tN = xn_root_mark();
#line 307 "tests/b3/fixtures/bundle_text/app.x"
int xn_tN = 1;
{
xn_root_restore(xn_tN);
}
{
xn_root_restore(xn_tN);
}

return xn_tN;

}
#line 308 "tests/b3/fixtures/bundle_text/app.x"
rt_string *c = xn_str_substr(xn_p_pattern, xn_p_pi, 1);
xn_root_add(c);
xn_root_add(c);
xn_root_add(c);
xn_gc_safepoint();
#line 309 "tests/b3/fixtures/bundle_text/app.x"
rt_string *xn_tN = rt_retain(c);
xn_root_add(xn_tN);
xn_root_add(xn_tN);
rt_string *xn_tN = rt_string_from_c("$");
xn_root_add(xn_tN);
xn_root_add(xn_tN);
if (((xn_str_eq(xn_tN, xn_tN)) && ((xn_p_pi == (plen - 1))))) {
size_t xn_tN = xn_root_mark();
#line 309 "tests/b3/fixtures/bundle_text/app.x"
int xn_tN = (xn_p_ti == xn_str_length(xn_p_text));
{
xn_root_restore(xn_tN);
}
{
rt_release(c);
}
{
xn_root_restore(xn_tN);
}

return xn_tN;

}
#line 310 "tests/b3/fixtures/bundle_text/app.x"
rt_string *next = rt_string_from_c("");
xn_root_add(next);
xn_root_add(next);
xn_gc_safepoint();
#line 311 "tests/b3/fixtures/bundle_text/app.x"
if ((((xn_p_pi + 1) < plen))) {
size_t xn_tN = xn_root_mark();
#line 311 "tests/b3/fixtures/bundle_text/app.x"
rt_string *xn_tN = xn_str_substr(xn_p_pattern, (xn_p_pi + 1), 1);
xn_root_add(xn_tN);
xn_root_add(xn_tN);
xn_root_release(next);
rt_release(next);
next = xn_tN;
xn_root_hold(next);
xn_gc_safepoint();
{
xn_root_restore(xn_tN);
}

}
#line 312 "tests/b3/fixtures/bundle_text/app.x"
rt_string *xn_tN = rt_retain(next);
xn_root_add(xn_tN);
xn_root_add(xn_tN);
rt_string *xn_tN = rt_string_from_c("*");
xn_root_add(xn_tN);
xn_root_add(xn_tN);
rt_string *xn_tN = rt_retain(next);
xn_root_add(xn_tN);
xn_root_add(xn_tN);
rt_string *xn_tN = rt_string_from_c("+");
xn_root_add(xn_tN);
xn_root_add(xn_tN);
rt_string *xn_tN = rt_retain(next);
xn_root_add(xn_tN);
xn_root_add(xn_tN);
rt_string *xn_tN = rt_string_from_c("?");
xn_root_add(xn_tN);
xn_root_add(xn_tN);
int quant = (((xn_str_eq(xn_tN, xn_tN)) || (xn_str_eq(xn_tN, xn_tN))) || (xn_str_eq(xn_tN, xn_tN)));
#line 313 "tests/b3/fixtures/bundle_text/app.x"
if ((quant)) {
size_t xn_tN = xn_root_mark();
#line 314 "tests/b3/fixtures/bundle_text/app.x"
int64_t nextp = (xn_p_pi + 2);
#line 315 "tests/b3/fixtures/bundle_text/app.x"
int64_t k = xn_p_ti;
#line 316 "tests/b3/fixtures/bundle_text/app.x"
int64_t count = 0;
#line 317 "tests/b3/fixtures/bundle_text/app.x"
while (1) {
rt_string *xn_tN = rt_retain(c);
xn_root_add(xn_tN);
xn_root_add(xn_tN);
rt_string *xn_tN = xn_str_substr(xn_p_text, k, 1);
xn_root_add(xn_tN);
xn_root_add(xn_tN);
xn_root_add(xn_tN);
if (!(((k < xn_str_length(xn_p_text))) && xn_regexAtomMatch(xn_tN, xn_tN))) { break; }
size_t xn_tN = xn_root_mark();
#line 318 "tests/b3/fixtures/bundle_text/app.x"
count = (count + 1);
#line 319 "tests/b3/fixtures/bundle_text/app.x"
k = (k + 1);
{
xn_root_restore(xn_tN);
}

xn_gc_safepoint();
}
#line 321 "tests/b3/fixtures/bundle_text/app.x"
int64_t min = 1;
#line 322 "tests/b3/fixtures/bundle_text/app.x"
int64_t max = count;
#line 323 "tests/b3/fixtures/bundle_text/app.x"
rt_string *xn_tN = rt_retain(next);
xn_root_add(xn_tN);
xn_root_add(xn_tN);
rt_string *xn_tN = rt_string_from_c("*");
xn_root_add(xn_tN);
xn_root_add(xn_tN);
if ((xn_str_eq(xn_tN, xn_tN))) {
size_t xn_tN = xn_root_mark();
#line 323 "tests/b3/fixtures/bundle_text/app.x"
min = 0;
{
xn_root_restore(xn_tN);
}

}
#line 324 "tests/b3/fixtures/bundle_text/app.x"
rt_string *xn_tN = rt_retain(next);
xn_root_add(xn_tN);
xn_root_add(xn_tN);
rt_string *xn_tN = rt_string_from_c("?");
xn_root_add(xn_tN);
xn_root_add(xn_tN);
if ((xn_str_eq(xn_tN, xn_tN))) {
size_t xn_tN = xn_root_mark();
#line 324 "tests/b3/fixtures/bundle_text/app.x"
min = 0;
#line 324 "tests/b3/fixtures/bundle_text/app.x"
if (((max > 1))) {
size_t xn_tN = xn_root_mark();
#line 324 "tests/b3/fixtures/bundle_text/app.x"
max = 1;
{
xn_root_restore(xn_tN);
}

}
{
xn_root_restore(xn_tN);
}

}
#line 325 "tests/b3/fixtures/bundle_text/app.x"
int64_t use = max;
#line 326 "tests/b3/fixtures/bundle_text/app.x"
while (((use >= min))) {
size_t xn_tN = xn_root_mark();
#line 327 "tests/b3/fixtures/bundle_text/app.x"
rt_string *xn_tN = rt_retain(xn_p_pattern);
xn_root_add(xn_tN);
xn_root_add(xn_tN);
rt_string *xn_tN = rt_retain(xn_p_text);
xn_root_add(xn_tN);
xn_root_add(xn_tN);
if ((xn_regexMatchAt(xn_tN, nextp, xn_tN, (xn_p_ti + use)))) {
size_t xn_tN = xn_root_mark();
#line 327 "tests/b3/fixtures/bundle_text/app.x"
int xn_tN = 1;
{
xn_root_restore(xn_tN);
}
{
xn_root_restore(xn_tN);
}
{
xn_root_restore(xn_tN);
}
{
rt_release(next);
}
{
rt_release(c);
}
{
xn_root_restore(xn_tN);
}

return xn_tN;

}
#line 328 "tests/b3/fixtures/bundle_text/app.x"
use = (use - 1);
{
xn_root_restore(xn_tN);
}

xn_gc_safepoint();
}
#line 330 "tests/b3/fixtures/bundle_text/app.x"
int xn_tN = 0;
{
xn_root_restore(xn_tN);
}
{
rt_release(next);
}
{
rt_release(c);
}
{
xn_root_restore(xn_tN);
}

return xn_tN;

}
#line 332 "tests/b3/fixtures/bundle_text/app.x"
if (((xn_p_ti >= xn_str_length(xn_p_text)))) {
size_t xn_tN = xn_root_mark();
#line 332 "tests/b3/fixtures/bundle_text/app.x"
int xn_tN = 0;
{
xn_root_restore(xn_tN);
}
{
rt_release(next);
}
{
rt_release(c);
}
{
xn_root_restore(xn_tN);
}

return xn_tN;

}
#line 333 "tests/b3/fixtures/bundle_text/app.x"
rt_string *xn_tN = rt_retain(c);
xn_root_add(xn_tN);
xn_root_add(xn_tN);
rt_string *xn_tN = xn_str_substr(xn_p_text, xn_p_ti, 1);
xn_root_add(xn_tN);
xn_root_add(xn_tN);
xn_root_add(xn_tN);
if ((xn_regexAtomMatch(xn_tN, xn_tN))) {
size_t xn_tN = xn_root_mark();
#line 333 "tests/b3/fixtures/bundle_text/app.x"
rt_string *xn_tN = rt_retain(xn_p_pattern);
xn_root_add(xn_tN);
xn_root_add(xn_tN);
rt_string *xn_tN = rt_retain(xn_p_text);
xn_root_add(xn_tN);
xn_root_add(xn_tN);
int xn_tN = xn_regexMatchAt(xn_tN, (xn_p_pi + 1), xn_tN, (xn_p_ti + 1));
{
xn_root_restore(xn_tN);
}
{
rt_release(next);
}
{
rt_release(c);
}
{
xn_root_restore(xn_tN);
}

return xn_tN;

}
#line 334 "tests/b3/fixtures/bundle_text/app.x"
int xn_tN = 0;
{
rt_release(c);
rt_release(next);
}
{
xn_root_restore(xn_tN);
}

return xn_tN;
}
