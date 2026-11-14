// 聚合工程最小构建（reactor）。
//
// 用法：
//   reactor build-project <dir> --xpd <xpd> --xmanifest <xmanifest>
//           --xnullc <xnullc> --xnast <xnast> --runtime <impl/runtime> --out <目标目录>
//
// 流程：
//   1. xpd 解析根与各模块清单 → TSV；
//   2. xmanifest 合成模块/依赖边/拓扑序；
//   3. 按拓扑序逐模块：xnast --ast → 原生 xnullc 生成 C；
//      library → cc -c（-Dmain=xn_unused_<模块> 避免与 app 的 main 冲突）；
//      app     → 记录 C，最后与全部 library 对象 + runtime + 空资源表链接。
//
// 未支持（后续）：build.entryFile、sourceRoot、跨模块 import、资源表（resman）、配置。
// 模块入口固定为 <dir>/<rel>/src/main/x/main.x。
package xdk.build.reactor
import xdk.sys

           
                   
                     
                   
                         
                   
                  
                     
 

            
                   
                           
                                       
                                
                               
                       
                      
                    
                      
                        
                      
 

// 文件名/符号名安全化：非字母数字一律换成下划线（`lib-core` → `lib_core`）。
static String safe(String rel) {
    String r = ""
    Int i = 0
    while i < rel.length() {
        String c = rel.substring(i, 1)
        Bytes b = Bytes.fromString(c)
        Int v = b.get(0)
        if v >= 48 && v <= 57 { r = r + c }
        else if v >= 65 && v <= 90 { r = r + c }
        else if v >= 97 && v <= 122 { r = r + c }
        else { r = r + "_" }
        i = i + 1
    }
    return r
}

static String resTable() {
    return "/* 由 xnull-build 生成：零资源工程空表（S8 §5.6） */\n"
    +"#include <stddef.h>\n"
    +"#include <string.h>\n"
    +"size_t xrt_resource_count(void) { return 0; }\n"
    +"int xrt_resource_get(const char *name, size_t nlen,\n"
    +"                     const unsigned char **out, size_t *out_len) {\n"
    +"    (void)name; (void)nlen;\n"
    +"    *out = 0; *out_len = 0;\n"
    +"    return 1;\n"
    +"}\n"
    +"int xrt_resource_at(size_t i, const char **name, size_t *nlen,\n"
    +"                    const unsigned char **out, size_t *out_len) {\n"
    +"    (void)i;\n"
    +"    *name = 0; *nlen = 0; *out = 0; *out_len = 0;\n"
    +"    return 1;\n"
    +"}\n"
}

static String groupOf(String coord) {
    Int i = 0
    while i < coord.length() {
        if coord.substring(i, 1) == ":" { return coord.substring(0, i) }
        i = i + 1
    }
    return coord
}

static String artifactOf(String coord) {
    Int i = 0
    while i < coord.length() {
        if coord.substring(i, 1) == ":" { return coord.substring(i + 1, coord.length() - i - 1) }
        i = i + 1
    }
    return coord
}

static String slashDots(String g) {
    String r = ""
    Int i = 0
    while i < g.length() {
        String c = g.substring(i, 1)
        if c == "." { r = r + "/" } else { r = r + c }
        i = i + 1
    }
    return r
}

// 读回 sha256（shasum 输出重定向到文件，procStatus 无法取 stdout）
static String shaOf(String path, String tmp) {
    Int32 rc = procStatus("shasum -a 256 \"" + path + "\" > \"" + tmp + "\"")
    if rc != 0 { return "" }
    String t = readFileText(tmp)
    String[] ps = t.split(" ")
    if ps.length() < 1 { return "" }
    return ps[0]
}

static String runtimeSrcs(String rt) {
    List<String> names = ["rt.c", "rt_gc.c", "rt_policy.c", "rt_weak.c", "xrt_abi.c",
        "rt_std_runtime.c", "rt_std_text.c", "rt_std_sys.c", "rt_std_bytes.c",
        "rt_std_net.c", "rt_task.c", "rt_sync.c", "rt_std_res.c", "rt_std_res_empty.c"]
    String s = ""
    Int i = 0
    while i < names.length() {
        s = s + " \"" + rt + "/" + names.get(i) + "\""
        i = i + 1
    }
    return s
}

               
                                                      
                                            
                                              
                                                   
                                                                           
                                  
                 
                                           
                                                          
                                                    
                                
                             
                      
                                      
                                                                      
                           
             
                                       
                                            
                                                                              
                                                  
                               
                                                  
                                     
                          
                                        
             
                           
                                                                                 
                                                     
             
                                                                                                           
                                                       
                                                                                      
                     
         
                                   
                                               
                         
                       
                       
                                         
                                    
                 
                               
                            
                                    
                                               
                                                             
                                                                   
                                                                         
                                                                      
                 
             
                     
         
                                     
                                        
                                                                                
                                                  
                                                                                             
                                                                                       
                                                             
         
     

                     
                                                             
                                                      
                    
         
                                                   
                                               
                                                                                                        
                                                          
                              
                                               
                                          
                 
                               
                            
                                    
                                               
                                                                                     
             
                     
         
                                     
             
                                 
                                                                    
                                                                                                                    
                                                                              
                        
                     
         
                                              
                                              
             
                                 
                                                  
                     
         
                                                     
                                                                     
                           
                         
                                              
                                           
             
                               
                            
                                    
                                               
                                                              
                                     
                                     
                                       
                                     
                                           
                                
                                                                    
                                     
                 
             
                     
         
                             
                        
                                          
                 
                                   
                                   
                         
             
         
                                         
                                       
                           
                                                
                     
                              
                                     
                                                                                                                    
                         
             
                                                   
                                                                                                                                                              
                                            
                             
                                                   
                                                        
                        
                                                       
                 
             
         
                                             
             
                                
                     
                             
                                     
                                                                    
                         
             
                                   
                                                 
                               
                                                                
                                                                                                                                 
                             
                                                         
                                                     
                              
                                            
                                             
                                                       
                                                                                                      
                                   
                     
                 
             
                                                                   
                               
                                     
                                                   
                        
             
                                                      
                         
                                                                                                                  
                                                                      
                                                                                                                                                        
                                                                       
                                     
                                                                                             
                    
                                                           
                               
                                                                                                                                                         
                                                                           
                                                                                              
             
                     
         
                                                    
                        
                         
             
                                
                     
                                     
                                                  
                                                       
                                              
                                                     
                                                                    
                     
                 
                         
             
                     
         
                        
                                            
                                        
                    
         
                                      
                                                                                                                                                                              
                              
                             
                                                       
                            
                                     
                             
                     
                             
                                     
                                                   
                                             
                             
                                       
                                              
                                                                                                                 
                                 
                     
                                                        
                 
                         
             
                            
                                                                                                               
             
         
                
     
 

static Int main(String[] args) {
    if args.length() < 2 || args[0] != "build-project" {
        print("reactor: 用法 build-project <dir> --runtime <rt> --out <dir> [--xpd P --xmanifest P --xnullc P --xnast P]")
        return 2
    }
    Args a = new Args()
    a.dir = args[1]
    Int i = 2
    while i < args.length() {
        String k = args[i]
        String v = ""
        if i + 1 < args.length() { v = args[i + 1] }
        if k == "--xpd" { a.xpd = v }
        else if k == "--xmanifest" { a.xmanifest = v }
        else if k == "--xnullc" { a.xnullc = v }
        else if k == "--xnast" { a.xnast = v }
        else if k == "--runtime" { a.runtime = v }
        else if k == "--out" { a.outdir = v }
        else if k == "--resman" { a.resman = v }
        else if k == "--artifact" { a.artifact = v }
        else if k == "--config" { a.config = v }
        else if k == "--repo" { a.repo = v }
        i = i + 2
    }
    Reactor r = new Reactor()
    return r.run(a)
}
