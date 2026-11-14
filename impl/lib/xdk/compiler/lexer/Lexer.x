// XNull 版词法器（Go xfront.Lex 的 L1 token dump 对照实现）。
// 只输出 token/AST 层数据，不依赖 Go xfront；lex 诊断以 code/line/col 输出。
// 覆盖：注释/BOM/CRLF、自动分号、数字/字符/字符串/插值（基础）、关键字、运算符。
package xdk.compiler.lexer; import xdk.text

static Bool inList(List<String> xs, String w) {
    Int i = 0
    while i < xs.length() {
        if xs.get(i) == w { return true }
        i = i + 1
    }
    return false
}

           
                
                    
                
               
               
                     
                          
                             
              
                
                      
                           
 

            
                    
                
               
                   
 

             
                   
               
               
                
               
                
                      
                        
                        
                         
                         
                         

                     
                    
                                        
                                       
                    
                     
                    
                                                                        
                                                                  
                        
         
     

                  
                                    
                     
         
                                
     

                
                                    
     

                                      
                         
                     
         
                                                     
     

                       
                                       
     

                
                       
                  
         
                                        
                               
                    
                                     
                        
                                       
                                   
         
     

                                                     
                           
                     
                  
                 
                   
                          
     

                                                     
                       
                                                                               
     
                              
                                                                       
     
                                                                              

                       
                      
                                 
                                            
                                             
                          
                               
                                 
                          
                                                             
                                                                     
                              
                 
                                                             
                                  
                                 
                          
                          
                                   
                                   
                                                                                     
                                  
                                  
                                     
                             
                     
                              
                 
                            
                                                         
                 
                    
                          
             
         
     

                            
                                                                                     
                                                          
                       
         
                        
                                                   
         
                        
                                                                                                       
         
                    
     

                                   
                         
                        
         
                                                                     
     

                                                 
                         
                     
                     
                  
                 
                
     

                
                          
                                 
                                  
                               
                             
         
                    
                             
                           
                                                                             
                                      
                                                                        
                 
                                                          
             
                                    
                             
                        
             
                                                                                                           
                                    
                              
                                  
                                                                    
             
                              
                         
                               
                    
         
     

                     
                         
                        
                                        
                          
                                                                                
                                                            
         
                                                                                                               
                                                           
         
                                                  
                                                            
         
                                                   
                                                            
         
                    
                                                             
         
                    
                                      
         
                            
                                        
         
                                 
                                
                      
                                                                             
                          
             
                                                     
                                     
                                             
             
                                         
         
                                                               
                      
                                
                      
                                                                             
                          
             
                                                                
         
                                  
                     
                                                     
         
                  
                                            
                                    
     

                      
                                                                                                         
                                                                                         
                                                                                                  
                                                             
                 
                                
                                 
                                 
                                                
                                                                                         
                                           
                                                
                                           
                        
                                                    
                 
                        
             
                     
         
                 
     

                             
                                              
                        
         
                                                            
     

                          
                                 
                                 
                                 
                                 
                                 
                                 
                                 
                                
                
     

                              
                                                                                                          
                                                                                           
                                                                                      
                                                                                                 
                                                                        
                            
     

                              
                 
                           
                                            
                        
                                                        
                                                                       
                 
                          
                        
             
                           
                                                
                                                         
                                                         
                                         
                               
                     
                      
         
                
     

                                  
                            
                     
                           
                             
                            
                                                                                                  
                     
                      
                      
                               
                                                                                                        
                    
                      
                      
                              
                                                                                                         
                    
                      
                      
                              
                
                               
         
                       
                                                                             
                          
                                   
                                                                      
                                                            
                                                                                                                            
                                  
                                                                                          
                                           
                     
                 
                                             
                                                                     
                          
                             
                                        
                        
             
         
                                     
                                                             
                     
                     
                
     

                         
                                   
                                        
                    
                      
                      
         
                    
                      
                      
         
                    
                      
                                                                 
                      
         
                 
     

                                
                  
                   
                     
                                                          
                      
                                               
                                       
         
                                                         
                                                   
                                       
         
                                           
                      
                            
                                                
                          
                                                                     
                                                                          
                                                                                                                              
                         
             
                
                                          
                      
                     
         
                                                          
                     
                                                                                                   
                          
             
         
                                                          
                      
                
                                                 
         
                                     
                                                      
         
                                    
                  
                
     

                                                                         
                                       
                  
                                               
                       
                          
                              
                                 
                           
                           
                                            
                                      
                     
             
                                   
                                                
                                          
                                   
                            
                 
                              
                                     
                        
                          
                                
                             
                                                
                                                    
                                 
                                         
                                         
                                  
                                        
                                         
                                       
                                      
                                
                                             
                                      
                         
                                       
                                          
                                  
                                          
                                                     
                                                            
                                        
                                                                
                                          
                                                
                                                                    
                                              
                                 
                                    
                                                                
                                          
                                                           
                             
                         
                            
                                                        
                                  
                     
                 
                                  
                        
             
                        
                              
                                                                                 
                                                          
                                     
                             
                     
                                                  
                              
                        
                              
                                 
                         
                 
                                       
                                  
                                 
                          
                                       
                                                
                          
                                                
                                                     
                                                     
                                                    
                                                    
                                                   
                                                        
                                                                                                 
                    
                                              
                          
             
         
                    
                                               
         
                      
                             
                    
                              
                                             
                                
                                      
                                    
                    
                        
                     
                           
                
     
 

String q(String s) {
    String b = "\""
    Int i = 0
    while i < s.length() {
        String c = s.substring(i, 1)
        if c == "\"" { b = b + "\\\"" }
        else if c == "\\" { b = b + "\\\\" }
        else if c == "\n" { b = b + "\\n" }
        else if c == "\t" { b = b + "\\t" }
        else if c == "\r" { b = b + "\\r" }
        else { b = b + c }
        i = i + 1
    }
    return b + "\""
}

String dumpTok(Tok t) {
    String b = "(Token (Kind " + str(t.kind) + ") (Text " + q(t.text)
    b = b + ") (Pos (Pos (Line " + str(t.line) + ") (Col " + str(t.col) + "))) (Str " + str(t.str)
    b = b + ") (Value " + q(t.value) + ") (Segs (slice"
    Int i = 0
    while i < t.segs.length() { b = b + " " + q(t.segs.get(i)); i = i + 1 }
    b = b + ")) (Interps (slice"
    i = 0
    while i < t.interps.length() { b = b + " " + q(t.interps.get(i)); i = i + 1 }
    b = b + ")) (Char " + str(t.ch) + ") (Base " + str(t.base) + ") (Suffix " + q(t.suffix) + ") (HasSuffixF "
    if t.hasSuffixF { b = b + "true" } else { b = b + "false" }
    return b + "))"
}

static Int main(String[] args) {
    if args.length() == 0 {
        print("xlex: 需要源码字符串")
        return 2
    }
    String mode = "tokens"
    String src = args[0]
    if src == "--diags" {
        mode = "diags"
        if args.length() < 2 {
            return 2
        }
        src = args[1]
    }
    Lexer l = new Lexer(src)
    if mode == "diags" {
        Bool go = true
        while go {
            Tok t = l.next()
            if t.kind == 0 { go = false }
        }
        print("xnast-diags-simple v1")
        Int i = 0
        while i < l.diags.length() {
            Diag d = l.diags.get(i)
            print(d.code + " " + str(d.line) + " " + str(d.col))
            i = i + 1
        }
        return 0
    }
    print("xnast-tokens v1")
    Bool go = true
    while go {
        Tok t = l.next()
        print(dumpTok(t))
        if t.kind == 0 { go = false }
    }
    return 0
}
