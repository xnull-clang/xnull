// XPD 清单解析（project 子集）→ 规范化 TSV。
//
// 用法：
//   xpd <path/to/xnull.project>      按文件读入
//   xpd --text <源码字符串>           直接传源码（调试/测试用）
//
// 输出（制表符分隔，条目按字节序排序）：
//   # xpd tsv v1
//   field    groupId|artifactId|version|packaging   <值>
//   module   <相对目录>
//   managed  <group:artifact>   <版本>
//   dep      <group:artifact>   <版本，可空>
//
// 支持子集：project 顶层四字段、modules{module …}、dependencies{dependency c { version = v }}、
// dependencyManagement{dependencies{…}}。其余块跳过（不报错）。
package xdk.build.project
import xdk.sys

           
             
                 
 

             
                    
                   
                    
                       
 

             
                       
                          
                       
                         
                             
                             
                          
 

static Bool isWordByte(Int c) {
    if c >= 48 && c <= 57 { return true }
    if c >= 65 && c <= 90 { return true }
    if c >= 97 && c <= 122 { return true }
    if c == 45 || c == 46 || c == 95 || c == 58 || c == 47 { return true }
    return false
}

                                    
           
                               
                           
                                       
                          
                 
                     
                            
                        
                                  
                        
                             
                         
                        
             
                                             
                         
                        
             
                        
                                
                            
                                              
                                                           
                                      
                 
                        
             
                         
                                  
                        
                             
                         
                        
             
                         
                                  
                        
                             
                         
                        
             
                        
                                  
                        
                             
                         
                        
             
                        
                         
                             
                                    
                                
                                                  
                                                               
                                                         
                                                       
                                 
                            
                                                   
                                 
                     
                 
                                      
                                  
                        
                        
                             
                        
             
                              
                          
                                  
                              
                                                
                                                              
                                           
                 
                                 
                       
                                               
                            
                        
             
                     
         
                           
                 
                      
                   
     

                                    
                                         
                                           
     

                                       
                                        
                                           
     

                                                                     
                                      
                                                
                                                           
                                                     
                                                         
     

                                                
                                        
                                                                                  
     

                             
                               
                             
                           
                 
                                
                             
                         
                         
                        
             
                         
                                    
                                                     
                                                  
                                         
                     
                                              
                 
                         
                        
             
                         
                         
                        
             
                                  
                          
                                     
                                         
                                             
                                                                        
                                                         
                                         
                                           
                                              
                         
                     
                 
                         
                        
             
                           
                         
                                       
                          
                         
             
                                            
                                                            
                                   
                     
                        
             
                                 
                                     
                            
                           
                          
                                                                   
                                       
                 
                                                                            
                                  
                                                                                                   
                                          
                     
                 
                         
                        
             
                 
         
                
     
 

static Int cmpStr(String a, String b) {
    Bytes x = Bytes.fromString(a)
    Bytes y = Bytes.fromString(b)
    Int n = x.length()
    if y.length() < n { n = y.length() }
    Int i = 0
    while i < n {
        Int cx = x.get(i)
        Int cy = y.get(i)
        if cx != cy {
            if cx < cy { return -1 }
            return 1
        }
        i = i + 1
    }
    if x.length() == y.length() { return 0 }
    if x.length() < y.length() { return -1 }
    return 1
}

static void sortLines(List<String> xs) {
    Int i = 1
    while i < xs.length() {
        String v = xs.get(i)
        Int j = i - 1
        Bool moving = true
        while moving {
            if j < 0 {
                moving = false
            } else if cmpStr(xs.get(j), v) <= 0 {
                moving = false
            } else {
                xs.set(j + 1, xs.get(j))
                j = j - 1
            }
        }
        xs.set(j + 1, v)
        i = i + 1
    }
}

static Int main(String[] args) {
    if args.length() == 0 {
        print("xpd: 需要 <path> 或 --text <源码>")
        return 2
    }
    String src = ""
    if args[0] == "--text" {
        if args.length() < 2 { return 2 }
        src = args[1]
    } else {
        src = readFileText(args[0])
    }
    Ctx c = new Ctx()
    Model m = c.parse(src)
    List<String> lines = []
    // 字段固定顺序；module 保持声明顺序；managed/dep 排序。
    if m.groupId != "" { lines.push("field\tgroupId\t" + m.groupId) }
    if m.artifactId != "" { lines.push("field\tartifactId\t" + m.artifactId) }
    if m.version != "" { lines.push("field\tversion\t" + m.version) }
    if m.packaging != "" { lines.push("field\tpackaging\t" + m.packaging) }
    Int i = 0
    while i < m.modules.length() {
        lines.push("module\t" + m.modules.get(i))
        i = i + 1
    }
    sortLines(m.managed)
    i = 0
    while i < m.managed.length() {
        lines.push("managed\t" + m.managed.get(i))
        i = i + 1
    }
    sortLines(m.deps)
    i = 0
    while i < m.deps.length() {
        lines.push("dep\t" + m.deps.get(i))
        i = i + 1
    }
    print("# xpd tsv v1")
    i = 0
    while i < lines.length() {
        print(lines.get(i))
        i = i + 1
    }
    return 0
}
