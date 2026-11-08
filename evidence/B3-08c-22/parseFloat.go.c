xn_Result_Double_Error xn_parseFloat(rt_string * xn_p_s) {
    xn_Result_Double_Error xn_ret;
size_t xn_t110 = xn_root_mark();
xn_root_add(xn_p_s);
#line 123 "tests/b3/fixtures/bundle_text/app.x"
int64_t n = xn_str_length(xn_p_s);
#line 124 "tests/b3/fixtures/bundle_text/app.x"
    if (((n == 0))) {
        size_t xn_t111 = xn_root_mark();
        #line 124 "tests/b3/fixtures/bundle_text/app.x"
        rt_string *xn_t112 = rt_string_from_c("parseFloat: 空串");
xn_root_add(xn_t112);
        xn_root_add(xn_t112);
        xn_root_add(xn_t112);
        xn_ret = (xn_Result_Double_Error){0, 0, xn_textErr(xn_t112)};
            {
        xn_root_restore(xn_t111);
            }
            {
        xn_root_restore(xn_t110);
            }

        return xn_ret;

    }
#line 125 "tests/b3/fixtures/bundle_text/app.x"
int64_t i = 0;
#line 126 "tests/b3/fixtures/bundle_text/app.x"
int neg = 0;
#line 127 "tests/b3/fixtures/bundle_text/app.x"
rt_string *xn_t113 = xn_str_substr(xn_p_s, 0, 1);
xn_root_add(xn_t113);
rt_string *xn_t114 = rt_string_from_c("-");
xn_root_add(xn_t114);
    if ((xn_str_eq(xn_t113, xn_t114))) {
        size_t xn_t115 = xn_root_mark();
        #line 127 "tests/b3/fixtures/bundle_text/app.x"
        neg = 1;
        #line 127 "tests/b3/fixtures/bundle_text/app.x"
        i = 1;
            {
            xn_root_restore(xn_t115);
            }

    } else {
        rt_string *xn_t117 = xn_str_substr(xn_p_s, 0, 1);
xn_root_add(xn_t117);
        xn_root_add(xn_t117);
        rt_string *xn_t118 = rt_string_from_c("+");
xn_root_add(xn_t118);
        xn_root_add(xn_t118);
            if ((xn_str_eq(xn_t117, xn_t118))) {
                size_t xn_t119 = xn_root_mark();
                #line 128 "tests/b3/fixtures/bundle_text/app.x"
                i = 1;
                    {
                    xn_root_restore(xn_t119);
                    }

            }
    }
#line 129 "tests/b3/fixtures/bundle_text/app.x"
double v = 0.0;
#line 130 "tests/b3/fixtures/bundle_text/app.x"
int any = 0;
#line 131 "tests/b3/fixtures/bundle_text/app.x"
    while (((i < n))) {
    size_t xn_t120 = xn_root_mark();
    #line 132 "tests/b3/fixtures/bundle_text/app.x"
    rt_string *ch = xn_str_substr(xn_p_s, i, 1);
xn_root_add(ch);
    xn_root_add(ch);
    xn_root_add(ch);
    xn_gc_safepoint();
    #line 133 "tests/b3/fixtures/bundle_text/app.x"
    rt_string *xn_t122 = rt_retain(ch);
xn_root_add(xn_t122);
    xn_root_add(xn_t122);
    rt_string *xn_t123 = rt_string_from_c(".");
xn_root_add(xn_t123);
    xn_root_add(xn_t123);
        if ((xn_str_eq(xn_t122, xn_t123))) {
            size_t xn_t124 = xn_root_mark();
            #line 133 "tests/b3/fixtures/bundle_text/app.x"
            xn_root_restore(xn_t124);
            xn_root_restore(xn_t120);
            break;
                {
                xn_root_restore(xn_t124);
                }

        }
    #line 134 "tests/b3/fixtures/bundle_text/app.x"
    rt_string *xn_t125 = rt_retain(ch);
xn_root_add(xn_t125);
    xn_root_add(xn_t125);
    rt_string *xn_t126 = rt_string_from_c("e");
xn_root_add(xn_t126);
    xn_root_add(xn_t126);
    rt_string *xn_t127 = rt_retain(ch);
xn_root_add(xn_t127);
    xn_root_add(xn_t127);
    rt_string *xn_t128 = rt_string_from_c("E");
xn_root_add(xn_t128);
    xn_root_add(xn_t128);
        if (((xn_str_eq(xn_t125, xn_t126)) || (xn_str_eq(xn_t127, xn_t128)))) {
            size_t xn_t129 = xn_root_mark();
            #line 134 "tests/b3/fixtures/bundle_text/app.x"
            xn_root_restore(xn_t129);
            xn_root_restore(xn_t120);
            break;
                {
                xn_root_restore(xn_t129);
                }

        }
    #line 135 "tests/b3/fixtures/bundle_text/app.x"
    rt_string *xn_t130 = rt_retain(ch);
xn_root_add(xn_t130);
    xn_root_add(xn_t130);
    double d = xn_digitOfD(xn_t130);
    #line 136 "tests/b3/fixtures/bundle_text/app.x"
        if (((d < 0.0))) {
            size_t xn_t131 = xn_root_mark();
            #line 136 "tests/b3/fixtures/bundle_text/app.x"
            rt_string *xn_t132 = rt_string_from_c("parseFloat: 非法字符");
xn_root_add(xn_t132);
    xn_root_add(xn_t132);
            xn_root_add(xn_t132);
            xn_root_add(xn_t132);
            xn_ret = (xn_Result_Double_Error){0, 0, xn_textErr(xn_t132)};
                {
            xn_root_restore(xn_t131);
                }
                {
            rt_release(ch);
                }
                {
            xn_root_restore(xn_t120);
                }
                {
            xn_root_restore(xn_t110);
                }

            return xn_ret;

        }
    #line 137 "tests/b3/fixtures/bundle_text/app.x"
    v = ((v * 10.0) + d);
    #line 138 "tests/b3/fixtures/bundle_text/app.x"
    any = 1;
    #line 139 "tests/b3/fixtures/bundle_text/app.x"
    i = (i + 1);
        {
        rt_release(ch);
        }
        {
        xn_root_restore(xn_t120);
        }

    xn_gc_safepoint();
    }
#line 141 "tests/b3/fixtures/bundle_text/app.x"
rt_string *xn_t133 = xn_str_substr(xn_p_s, i, 1);
xn_root_add(xn_t133);
rt_string *xn_t134 = rt_string_from_c(".");
xn_root_add(xn_t134);
    if ((((i < n)) && (xn_str_eq(xn_t133, xn_t134)))) {
        size_t xn_t135 = xn_root_mark();
        #line 142 "tests/b3/fixtures/bundle_text/app.x"
        i = (i + 1);
        #line 143 "tests/b3/fixtures/bundle_text/app.x"
        double scale = 0.1;
        #line 144 "tests/b3/fixtures/bundle_text/app.x"
            while (((i < n))) {
            size_t xn_t136 = xn_root_mark();
            #line 145 "tests/b3/fixtures/bundle_text/app.x"
            rt_string *ch = xn_str_substr(xn_p_s, i, 1);
xn_root_add(ch);
        xn_root_add(ch);
            xn_root_add(ch);
            xn_root_add(ch);
            xn_gc_safepoint();
            #line 146 "tests/b3/fixtures/bundle_text/app.x"
            rt_string *xn_t138 = rt_retain(ch);
xn_root_add(xn_t138);
        xn_root_add(xn_t138);
            xn_root_add(xn_t138);
            rt_string *xn_t139 = rt_string_from_c("e");
xn_root_add(xn_t139);
        xn_root_add(xn_t139);
            xn_root_add(xn_t139);
            rt_string *xn_t140 = rt_retain(ch);
xn_root_add(xn_t140);
        xn_root_add(xn_t140);
            xn_root_add(xn_t140);
            rt_string *xn_t141 = rt_string_from_c("E");
xn_root_add(xn_t141);
        xn_root_add(xn_t141);
            xn_root_add(xn_t141);
                if (((xn_str_eq(xn_t138, xn_t139)) || (xn_str_eq(xn_t140, xn_t141)))) {
                    size_t xn_t142 = xn_root_mark();
                    #line 146 "tests/b3/fixtures/bundle_text/app.x"
                    xn_root_restore(xn_t142);
                    xn_root_restore(xn_t136);
                    break;
                        {
                        xn_root_restore(xn_t142);
                        }

                }
            #line 147 "tests/b3/fixtures/bundle_text/app.x"
            rt_string *xn_t143 = rt_retain(ch);
xn_root_add(xn_t143);
        xn_root_add(xn_t143);
            xn_root_add(xn_t143);
            double d = xn_digitOfD(xn_t143);
            #line 148 "tests/b3/fixtures/bundle_text/app.x"
                if (((d < 0.0))) {
                    size_t xn_t144 = xn_root_mark();
                    #line 148 "tests/b3/fixtures/bundle_text/app.x"
                    rt_string *xn_t145 = rt_string_from_c("parseFloat: 非法小数");
xn_root_add(xn_t145);
        xn_root_add(xn_t145);
            xn_root_add(xn_t145);
                    xn_root_add(xn_t145);
                    xn_root_add(xn_t145);
                    xn_ret = (xn_Result_Double_Error){0, 0, xn_textErr(xn_t145)};
                        {
                    xn_root_restore(xn_t144);
                        }
                        {
                    rt_release(ch);
                        }
                        {
                    xn_root_restore(xn_t136);
                        }
                        {
                    xn_root_restore(xn_t135);
                        }
                        {
                    xn_root_restore(xn_t110);
                        }

                    return xn_ret;

                }
            #line 149 "tests/b3/fixtures/bundle_text/app.x"
            v = (v + (d * scale));
            #line 150 "tests/b3/fixtures/bundle_text/app.x"
            scale = (scale * 0.1);
            #line 151 "tests/b3/fixtures/bundle_text/app.x"
            any = 1;
            #line 152 "tests/b3/fixtures/bundle_text/app.x"
            i = (i + 1);
                {
                rt_release(ch);
                }
                {
                xn_root_restore(xn_t136);
                }

            xn_gc_safepoint();
            }
            {
            xn_root_restore(xn_t135);
            }

    }
#line 155 "tests/b3/fixtures/bundle_text/app.x"
    if (((!(any)))) {
        size_t xn_t146 = xn_root_mark();
        #line 155 "tests/b3/fixtures/bundle_text/app.x"
        rt_string *xn_t147 = rt_string_from_c("parseFloat: 缺少数字");
xn_root_add(xn_t147);
        xn_root_add(xn_t147);
        xn_root_add(xn_t147);
        xn_ret = (xn_Result_Double_Error){0, 0, xn_textErr(xn_t147)};
            {
        xn_root_restore(xn_t146);
            }
            {
        xn_root_restore(xn_t110);
            }

        return xn_ret;

    }
#line 156 "tests/b3/fixtures/bundle_text/app.x"
rt_string *xn_t148 = xn_str_substr(xn_p_s, i, 1);
xn_root_add(xn_t148);
rt_string *xn_t149 = rt_string_from_c("e");
xn_root_add(xn_t149);
rt_string *xn_t150 = xn_str_substr(xn_p_s, i, 1);
xn_root_add(xn_t150);
rt_string *xn_t151 = rt_string_from_c("E");
xn_root_add(xn_t151);
    if ((((i < n)) && ((xn_str_eq(xn_t148, xn_t149) || xn_str_eq(xn_t150, xn_t151))))) {
        size_t xn_t152 = xn_root_mark();
        #line 157 "tests/b3/fixtures/bundle_text/app.x"
        i = (i + 1);
        #line 158 "tests/b3/fixtures/bundle_text/app.x"
        int eneg = 0;
        #line 159 "tests/b3/fixtures/bundle_text/app.x"
        rt_string *xn_t153 = xn_str_substr(xn_p_s, i, 1);
xn_root_add(xn_t153);
        xn_root_add(xn_t153);
        rt_string *xn_t154 = rt_string_from_c("-");
xn_root_add(xn_t154);
        xn_root_add(xn_t154);
            if ((((i < n)) && (xn_str_eq(xn_t153, xn_t154)))) {
                size_t xn_t155 = xn_root_mark();
                #line 159 "tests/b3/fixtures/bundle_text/app.x"
                eneg = 1;
                #line 159 "tests/b3/fixtures/bundle_text/app.x"
                i = (i + 1);
                    {
                    xn_root_restore(xn_t155);
                    }

            } else {
                rt_string *xn_t157 = xn_str_substr(xn_p_s, i, 1);
xn_root_add(xn_t157);
        xn_root_add(xn_t157);
                xn_root_add(xn_t157);
                rt_string *xn_t158 = rt_string_from_c("+");
xn_root_add(xn_t158);
        xn_root_add(xn_t158);
                xn_root_add(xn_t158);
                    if ((((i < n)) && (xn_str_eq(xn_t157, xn_t158)))) {
                        size_t xn_t159 = xn_root_mark();
                        #line 160 "tests/b3/fixtures/bundle_text/app.x"
                        i = (i + 1);
                            {
                            xn_root_restore(xn_t159);
                            }

                    }
            }
        #line 161 "tests/b3/fixtures/bundle_text/app.x"
            if (((i >= n))) {
                size_t xn_t160 = xn_root_mark();
                #line 161 "tests/b3/fixtures/bundle_text/app.x"
                rt_string *xn_t161 = rt_string_from_c("parseFloat: 指数缺少数字");
xn_root_add(xn_t161);
        xn_root_add(xn_t161);
                xn_root_add(xn_t161);
                xn_root_add(xn_t161);
                xn_ret = (xn_Result_Double_Error){0, 0, xn_textErr(xn_t161)};
                    {
                xn_root_restore(xn_t160);
                    }
                    {
                xn_root_restore(xn_t152);
                    }
                    {
                xn_root_restore(xn_t110);
                    }

                return xn_ret;

            }
        #line 162 "tests/b3/fixtures/bundle_text/app.x"
        int64_t e = 0;
        #line 163 "tests/b3/fixtures/bundle_text/app.x"
            while (((i < n))) {
            size_t xn_t162 = xn_root_mark();
            #line 164 "tests/b3/fixtures/bundle_text/app.x"
            rt_string *xn_t163 = xn_str_substr(xn_p_s, i, 1);
xn_root_add(xn_t163);
        xn_root_add(xn_t163);
            xn_root_add(xn_t163);
            int64_t d = xn_digitOf(xn_t163);
            #line 165 "tests/b3/fixtures/bundle_text/app.x"
                if (((d < 0))) {
                    size_t xn_t164 = xn_root_mark();
                    #line 165 "tests/b3/fixtures/bundle_text/app.x"
                    rt_string *xn_t165 = rt_string_from_c("parseFloat: 非法指数");
xn_root_add(xn_t165);
        xn_root_add(xn_t165);
            xn_root_add(xn_t165);
                    xn_root_add(xn_t165);
                    xn_root_add(xn_t165);
                    xn_ret = (xn_Result_Double_Error){0, 0, xn_textErr(xn_t165)};
                        {
                    xn_root_restore(xn_t164);
                        }
                        {
                    xn_root_restore(xn_t162);
                        }
                        {
                    xn_root_restore(xn_t152);
                        }
                        {
                    xn_root_restore(xn_t110);
                        }

                    return xn_ret;

                }
            #line 166 "tests/b3/fixtures/bundle_text/app.x"
            e = ((e * 10) + d);
            #line 167 "tests/b3/fixtures/bundle_text/app.x"
            i = (i + 1);
                {
                xn_root_restore(xn_t162);
                }

            xn_gc_safepoint();
            }
        #line 169 "tests/b3/fixtures/bundle_text/app.x"
        int64_t k = 0;
        #line 170 "tests/b3/fixtures/bundle_text/app.x"
            while (((k < e))) {
            size_t xn_t166 = xn_root_mark();
            #line 171 "tests/b3/fixtures/bundle_text/app.x"
                if ((eneg)) {
                    size_t xn_t167 = xn_root_mark();
                    #line 171 "tests/b3/fixtures/bundle_text/app.x"
                    v = xn_div_i64((int64_t)(v), (int64_t)(10.0));
                        {
                        xn_root_restore(xn_t167);
                        }

                } else {
                    size_t xn_t168 = xn_root_mark();
                    #line 171 "tests/b3/fixtures/bundle_text/app.x"
                    v = (v * 10.0);
                        {
                        xn_root_restore(xn_t168);
                        }

                }
            #line 172 "tests/b3/fixtures/bundle_text/app.x"
            k = (k + 1);
                {
                xn_root_restore(xn_t166);
                }

            xn_gc_safepoint();
            }
            {
            xn_root_restore(xn_t152);
            }

    }
#line 175 "tests/b3/fixtures/bundle_text/app.x"
    if (((i != n))) {
        size_t xn_t169 = xn_root_mark();
        #line 175 "tests/b3/fixtures/bundle_text/app.x"
        rt_string *xn_t170 = rt_string_from_c("parseFloat: 未消费完整字符串");
xn_root_add(xn_t170);
        xn_root_add(xn_t170);
        xn_root_add(xn_t170);
        xn_ret = (xn_Result_Double_Error){0, 0, xn_textErr(xn_t170)};
            {
        xn_root_restore(xn_t169);
            }
            {
        xn_root_restore(xn_t110);
            }

        return xn_ret;

    }
#line 176 "tests/b3/fixtures/bundle_text/app.x"
    if ((neg)) {
        size_t xn_t171 = xn_root_mark();
        #line 176 "tests/b3/fixtures/bundle_text/app.x"
        xn_ret = (xn_Result_Double_Error){1, (0.0 - v), 0};
            {
        xn_root_restore(xn_t171);
            }
            {
        xn_root_restore(xn_t110);
            }

        return xn_ret;

    }
#line 177 "tests/b3/fixtures/bundle_text/app.x"
xn_ret = (xn_Result_Double_Error){1, v, 0};
    {
xn_root_restore(xn_t110);
    }

return xn_ret;
}
