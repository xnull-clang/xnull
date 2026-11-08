# xnullc.x root/release 发射站点（只读盘点）

共 126 处，按函数分组。

## rootStr（2）
- L1044: `e.raw("xn_root_add(" + t + ");")`
- L1045: `if sc.doubleRoot { e.add("xn_root_add(" + t + ");") }`

## argExpr（2）
- L1051: `if a.nm == "Call" && sc.curFn != "regexMatchAt" { e.add("xn_root_add(" + at + ");") }`
- L1052: `if a.nm == "IdentExpr" && sc.curFn == "regexMatchAt" && sc.inRet && sc.blockRoots.length() >= 1 { e.add("xn_root_add(" + at + ");") }`

## expr（2）
- L1141: `e.add("rt_release(" + sv + ");")`
- L1374: `e.raw("xn_root_add(" + t + ");")`

## emitPrint（4）
- L1593: `while i < extraRoots { e.add("xn_root_add(" + t + ");"); i = i + 1 }`
- L1595: `e.add("rt_release(" + t + ");")`
- L1612: `e.add("rt_release(" + t + ");")`
- L1620: `e.add("rt_release(" + t + ");")`

## emitDeferBody（9）
- L1641: `e.raw("xn_root_add(" + d.temp + ");")`
- L1642: `e.raw("xn_root_add(" + d.temp + ");")`
- L1643: `e.addAt(base + 8, "xn_root_add(" + d.temp + ");")`
- L1645: `e.addAt(base + 8, "rt_release(" + d.temp + ");")`
- L1648: `e.raw("xn_root_add(" + d.temp + ");")`
- L1649: `e.addAt(base, "xn_root_add(" + d.temp + ");")`
- L1650: `e.addAt(base, "xn_root_add(" + d.temp + ");")`
- L1651: `e.addAt(base + 8, "xn_root_add(" + d.temp + ");")`
- L1653: `e.addAt(base + 8, "rt_release(" + d.temp + ");")`

## emitBlockDefers（3）
- L1664: `e.raw("xn_root_add(" + d.temp + ");")`
- L1665: `e.addAt(ind + 12, "xn_root_add(" + d.temp + ");")`
- L1667: `e.addAt(ind + 12, "rt_release(" + d.temp + ");")`

## emitEarlyRet（3）
- L1691: `e.addAt(e.ind, "xn_root_restore(" + sc.blockRoots.get(bri) + ");")`
- L1699: `e.addAt(e.ind, "rt_release(" + sc.strLocals.get(sri) + ");")`
- L1704: `e.addAt(e.ind, "xn_root_restore(" + sc.root + ");")`

## emitStmt（4）
- L1758: `Bool isAdd = t.indexOf("xn_root_add(") == 0`
- L1766: `resL.push(sp(8 + 4 * pendEc) + "xn_root_add(" + pendNm + ");")`
- L1772: `if t.indexOf("xn_root_hold(") >= 0 { i = i + 1; continue }`
- L1781: `if pendNm != "" { resL.push(sp(8 + 4 * pendEc) + "xn_root_add(" + pendNm + ");") }`

## emitStmtInner（71）
- L1809: `e.add("xn_root_restore(" + sc.blockRoots.get(bi) + ");")`
- L1837: `e.addAt(e.ind + 8, "xn_root_restore(" + sc.root + ");")`
- L1854: `e.raw("xn_root_add(" + bt + ");")`
- L1855: `e.add("rt_release(" + bs + ");")`
- L1857: `e.raw("xn_root_add(" + nm + ");")`
- L1858: `e.raw("xn_root_add(" + nm + ");")`
- L1900: `e.raw("xn_root_add(" + nm + ");")`
- L1901: `e.add("xn_root_add(" + nm + ");")`
- L1902: `if sc.curFn != "regexMatchAt" { e.add("xn_root_add(" + nm + ");") }`
- L1904: `e.raw("xn_root_add(" + nm + ");")`
- L1905: `e.raw("xn_root_add(" + nm + ");")`
- L1916: `e.raw("xn_root_add(" + t + ");")`
- L1920: `e.raw("xn_root_add(" + nm + ");")`
- L1921: `e.raw("xn_root_add(" + nm + ");")`
- L1932: `e.raw("xn_root_add(" + t + ");")`
- L1936: `e.raw("xn_root_add(" + nm + ");")`
- L1937: `e.raw("xn_root_add(" + nm + ");")`
- L1947: `e.raw("xn_root_add(" + t + ");")`
- L1951: `e.raw("xn_root_add(" + nm + ");")`
- L1952: `e.raw("xn_root_add(" + nm + ");")`
- L1965: `e.raw("xn_root_add(" + nm + ");")`
- L1966: `e.raw("xn_root_add(" + nm + ");")`
- L1975: `e.raw("xn_root_add(" + ta + ");")`
- L1980: `e.raw("xn_root_add(" + ts + ");")`
- L1983: `e.raw("xn_root_add(" + nm + ");")`
- L1984: `e.raw("xn_root_add(" + nm + ");")`
- L1994: `e.raw("xn_root_add(" + tm + ");")`
- L2003: `e.raw("xn_root_add(" + nm + ");")`
- L2004: `e.raw("xn_root_add(" + nm + ");")`
- L2011: `e.raw("xn_root_add(" + nm + ");")`
- L2067: `e.raw("xn_root_add(" + nm + ");")`
- L2069: `sc.releases.push("rt_release((void *)" + nm + ");")`
- L2085: `e.raw("xn_root_add(" + nm + ");")`
- L2096: `e.raw("xn_root_add(" + nm + ");")`
- L2098: `e.raw("xn_root_add(" + nm + ");")`
- L2100: `} else { sc.releases.push("rt_release(" + nm + ");") }`
- L2107: `e.raw("xn_root_add(" + nm + ");")`
- L2108: `sc.releases.push("rt_release(" + nm + ");")`
- L2112: `e.raw("xn_root_add(" + nm + ");")`
- L2113: `if isGC { e.raw("xn_root_add(" + nm + ");"); e.raw("xn_gc_safepoint();") }`
- L2114: `else { sc.releases.push("rt_release(" + nm + ");") }`
- L2156: `e.add("rt_release((void *)" + mnm + ");")`
- L2167: `e.raw("xn_root_add(" + t + ");")`
- L2168: `e.add("rt_release(" + mnm + ");")`
- L2192: `e.add("xn_root_release(" + nm + ");")`
- L2193: `e.add("rt_release(" + nm + ");")`
- L2195: `e.add("xn_root_hold(" + nm + ");")`
- L2204: `e.add("rt_release(" + nm + ");")`
- L2307: `while i < 2 { e.add("xn_root_add(" + ev + ");"); i = i + 1 }`
- L2320: `e.addAt(lind, "xn_root_add(" + mt + ");")`
- L2324: `e.add("xn_root_add(" + mt + ");")`
- L2325: `e.add("xn_root_add(" + mt + ");")`
- L2343: `e.addAt(e.ind, "xn_root_restore(" + sc.blockRoots.get(rb) + ");")`
- L2352: `e.addAt(e.ind, "rt_release(" + sc.strLocals.get(sri3) + ");")`
- L2358: `e.addAt(e.ind, "xn_root_restore(" + sc.root + ");")`
- L2378: `if !sc.doubleRoot { e.add("xn_root_add(" + stx + ");") }`
- L2379: `if early { e.add("xn_root_add(" + stx + ");") }`
- L2390: `e.raw("xn_root_add(" + nt0 + ");")`
- L2391: `e.add("xn_root_add(" + nt0 + ");")`
- L2392: `e.add("xn_root_add(" + nt0 + ");")`
- L2394: `e.raw("xn_root_add(" + nt0 + ");")`
- L2395: `e.raw("xn_root_add(" + nt0 + ");")`
- L2431: `if !sc.doubleRoot { e.add("xn_root_add(" + t + ");") }`
- L2432: `if early { e.add("xn_root_add(" + t + ");") }`
- L2475: `e.addAt(e.ind + 12, "xn_root_restore(" + r + ");")`
- L2514: `e.addAt(e.ind + 12, "xn_root_restore(" + r2 + ");")`
- L2558: `e.addAt(e.ind + 12, "xn_root_restore(" + rl + ");")`
- L2580: `e.addAt(e.ind + 8, "xn_root_restore(" + r + ");")`
- L2604: `e.addAt(e.ind + 8, "xn_root_restore(" + bodyRoot + ");")`
- L2637: `e.addAt(e.ind + 16, "xn_root_restore(" + r + ");")`
- L2662: `e.addAt(e.ind + 16, "xn_root_restore(" + r + ");")`

## emitFunc（5）
- L2897: `if needRoot { e.raw("xn_root_add(xn_p_" + pnm + ");") }`
- L2916: `e.raw("rt_release(" + sc.strLocals.get(si0) + ");")`
- L2924: `e.raw("rt_release(" + sc.strLocals.get(si1) + ");")`
- L2930: `e.raw("xn_root_restore(" + root + ");")`
- L2936: `if sc.curFn == "regexMatchAt" { while hdi < sc.held.length() { e.raw("xn_root_release(" + sc.held.get(hdi) + ");"); hdi = hdi + 1 } }`

## emitClassSection（10）
- L3129: `ce.addAt(0, "xn_root_restore(" + mr + ");")`
- L3154: `ce.addAt(4, "rt_release((void *)o->" + fn + ");")`
- L3178: `if ref { ce.raw("xn_root_add(o);") }`
- L3187: `if proot { ce.raw("xn_root_add(xn_p_" + unq(txt(fld(cps.el.get(pj), "Name"))) + ");") }`
- L3206: `ce.addAt(4, "xn_root_restore(" + root + ");")`
- L3262: `if ref && !stat { ce.raw("xn_root_add(self);") }`
- L3268: `if proot0 { ce.raw("xn_root_add(xn_p_" + unq(txt(fld(mps.el.get(mj), "Name"))) + ");") }`
- L3282: `ce.raw("rt_release(" + msc.strLocals.get(mri) + ");")`
- L3287: `if mn == "deinit" { ce.addAt(4, "xn_root_restore(" + mr + ");") } else { ce.addAt(0, "xn_root_restore(" + mr + ");") }`
- L3293: `if rt == "String" && inNames(msc.strLocals, msc.ret) { ce.raw("xn_root_release(" + msc.ret + ");") }`

## emitStructMethods（1）
- L3401: `ce.addAt(0, "xn_root_restore(" + mr + ");")`

## emitExtensionMethods（2）
- L3443: `ce.raw("xn_root_add(self);")`
- L3446: `ce.addAt(0, "xn_root_restore(" + mr + ");")`

## emitFactoryMethods（2）
- L3490: `if cType(pt).length() > 0 && cType(pt).substring(cType(pt).length() - 1, 1) == "*" { ce.raw("xn_root_add(xn_p_" + unq(txt(fld(mps.el.get(mj), "Name"))) + ");") }`
- L3495: `ce.addAt(0, "xn_root_restore(" + r + ");")`

## emitDataEnum（2）
- L3543: `e.raw("xn_root_add(o);")`
- L3559: `e.addAt(4, "xn_root_restore(" + rt + ");")`

## emitDataEnumMethods（2）
- L3604: `e.raw("xn_root_add(self);")`
- L3607: `e.addAt(0, "xn_root_restore(" + r + ");")`

## emitSingletonSection（2）
- L3701: `if ref { ce.raw("xn_root_add(self);") }`
- L3704: `ce.addAt(0, "xn_root_restore(" + mr + ");")`
