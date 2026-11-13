   {t:"xdk.time（对标 Go time + Python datetime）",s:"todo",c:[
     {t:"时钟",s:"todo",c:[
       {t:"now() → DateTime / nowMono() / nowWall() / millis() / micros()",s:"todo"}
     ]},
     {t:"DateTime 类",s:"todo",c:[
       {t:"DateTime.of(y,mo,d,h,mi,s) / fromTimestamp(ms)",s:"todo"},
       {t:"year()/month()/day()/hour()/minute()/second()/millis()",s:"todo"},
       {t:"weekday()/dayOfYear()/timestamp()/toUTC()/toLocal()",s:"todo"},
       {t:"add(d)/diff(other)→Duration/before/after/compare",s:"todo"}
     ]},
     {t:"格式化与解析",s:"todo",c:[
       {t:"format(layout) → String（yyyy-MM-dd HH:mm:ss）",s:"todo"},
       {t:"parse(layout,s) → Result<DateTime,Error>",s:"todo"},
       {t:"iso8601() / rfc3339()",s:"todo"}
     ]},
     {t:"Duration 类",s:"todo",c:[
       {t:"ofSeconds/ofMillis/ofMinutes/ofHours/ofDays",s:"todo"},
       {t:"seconds()/millis()/micros()/plus()/minus()",s:"todo"}
     ]},
     {t:"定时器",s:"todo",c:[
       {t:"sleep(d)/after(d,f)/every(d,f)→Timer/Timer.cancel()",s:"todo"}
     ]}
   ]},
   {t:"xdk.codec（编解码 · 对标 Python base64/json/struct + Go encoding/*）",s:"todo",c:[
     {t:"Hex / Base64",s:"todo",c:[
       {t:"hexEncode(b)/hexDecode(s)→Result<Bytes,Error>",s:"todo"},
       {t:"base64Encode(b)/base64Decode(s)→Result<Bytes,Error>",s:"todo"},
       {t:"base64UrlEncode/base64UrlDecode（无填充）",s:"todo"}
     ]},
     {t:"URL 编码",s:"todo",c:[
       {t:"urlEncode(s)/urlDecode(s)",s:"todo"},
       {t:"queryEscape/queryUnescape/buildQuery(map)",s:"todo"}
     ]},
     {t:"JSON",s:"todo",c:[
       {t:"jsonParse(s)→Result<JsonValue,Error>/jsonStringify(v)→String",s:"todo"},
       {t:"JsonValue.get(key)/at(i)/asInt/asDouble/asBool/asString/asList/asMap",s:"todo"},
       {t:"JsonValue.str()（str 改名体系）/pretty(indent)",s:"todo"}
     ]},
     {t:"CSV",s:"todo",c:[
       {t:"csvParse(s)→Result<List<List<String>>,Error>",s:"todo"},
       {t:"csvEncode(rows,sep)→String",s:"todo"}
     ]},
     {t:"二进制（对标 struct）",s:"todo",c:[
       {t:"BinaryReader.readU8/U16/U32/U64/I32/F32/F64（LE/BE）",s:"todo"},
       {t:"BinaryWriter.writeU8/…/writeString/writeBytes",s:"todo"},
       {t:"BinaryReader.seek/tell/remaining/eof",s:"todo"}
     ]}
   ]},
