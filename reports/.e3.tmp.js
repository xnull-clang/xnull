   {t:"xdk.text 扩展（对标 Java StringUtils + Go strings）",s:"todo",c:[
     {t:"Strings 工具函数",s:"todo",c:[
       {t:"join(xs,sep)/contains(s,sub)/count(s,sub)/repeat(s,n)",s:"todo"},
       {t:"padLeft(s,n,ch)/padRight(s,n,ch)/reverse(s)",s:"todo"},
       {t:"isEmpty(s)/isBlank(s)/equalsIgnoreCase(a,b)",s:"todo"},
       {t:"levenshtein(a,b)/truncate(s,n)/capitalize(s)",s:"todo"}
     ]},
     {t:"StringBuilder（可变字符串）",s:"todo",c:[
       {t:"append(v)/appendLine(v)/insert(i,v)/delete(i,n)",s:"todo"},
       {t:"length()/clear()/charAt(i)/str()（输出）",s:"todo"}
     ]},
     {t:"Char 分类与 Unicode",s:"todo",c:[
       {t:"isDigit/isAlpha/isSpace/isUpper/isLower/isHexDigit",s:"todo"},
       {t:"codePoints(s)→List<Int>/fromCodePoint(cp)→String",s:"todo"}
     ]},
     {t:"Regex 完整面",s:"todo",c:[
       {t:"find(s)→Match?/findAll(s)→List<Match>",s:"todo"},
       {t:"replaceAll(s,repl)/split(s)/group(i)/namedGroup(name)",s:"todo"}
     ]}
   ]},
   {t:"xdk.sys 扩展（对标 Python os/pathlib/subprocess + Go os）",s:"todo",c:[
     {t:"文件操作",s:"todo",c:[
       {t:"readFileText/writeFileText/appendFile/readBytes/writeBytes",s:"todo"},
       {t:"fileExists/remove/rename/copy/fileSize/mtime",s:"todo"}
     ]},
     {t:"目录操作",s:"todo",c:[
       {t:"listDir(path)→List<String>/mkdir/mkdirAll/removeDir",s:"todo"},
       {t:"walk(path)→List<String>/cwd()/chdir(path)",s:"todo"}
     ]},
     {t:"Path 类（路径处理）",s:"todo",c:[
       {t:"Path.join(parts)/dirname/basename/ext/stem",s:"todo"},
       {t:"absolute()/clean()/isAbsolute()/relativeTo(base)",s:"todo"}
     ]},
     {t:"标准流",s:"todo",c:[
       {t:"stdin.readLine()→String?/stdin.readAll()",s:"todo"},
       {t:"stdout.write(s)/stderr.write(s)/flush()",s:"todo"}
     ]},
     {t:"进程",s:"todo",c:[
       {t:"run(cmd,args)→Result<ExitStatus,Error>（捕获输出）",s:"todo"},
       {t:"spawn(cmd,args)→Process/kill/wait/pipe",s:"todo"}
     ]},
     {t:"环境与参数",s:"todo",c:[
       {t:"args()→List<String>/env(name)/setEnv/hasEnv",s:"todo"},
       {t:"hostname()/platform()/arch()/pid()",s:"todo"}
     ]}
   ]},
