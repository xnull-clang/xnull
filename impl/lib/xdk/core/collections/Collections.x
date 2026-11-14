// xdk.collections —— S6-07 源码单元（算法 + 4 个特化容器）
// 设计口径：
//   - 算法用比较/相等/键提取回调表达，不要求 T 可比较；
//   - 容器为纯 XNull 值类型封装（内部用 List），语义优先、复杂度为首版实现；
//   - 不改变内建容器语义（S1 §9）。
package xdk.collections
// sortBy：按 less(a,b) 升序插入排序，原地修改并返回。
List<T> sortBy<T>(List<T> xs, Bool(T, T) less) {
    Int i = 1
    while i < xs.length() {
        T v = xs.get(i)
        Int j = i - 1
        while j >= 0 {
            if less(v, xs.get(j)) {
                xs.set(j + 1, xs.get(j))
                j = j - 1
            } else {
                break
            }
        }
        xs.set(j + 1, v)
        i = i + 1
    }
    return xs
}

// dedup：按 eq 去重，保留首次出现顺序。
List<T> dedup<T>(List<T> xs, Bool(T, T) eq) {
    List<T> res = []
    for x in xs {
        Bool seen = false
        for y in res {
            if eq(x, y) {
                seen = true
                break
            }
        }
        if !seen {
            res.push(x)
        }
    }
    return res
}

// find：返回首个满足 pred 的元素；不存在返回 null。
T? find<T>(List<T> xs, Bool(T) pred) {
    for x in xs {
        if pred(x) {
            return x
        }
    }
    return null
}

// groupByInt：按 Int 键分组，保持元素相对顺序。
Map<Int, List<T>> groupByInt<T>(List<T> xs, Int(T) key) {
    Map<Int, List<T>> groups = [:]
    for x in xs {
        Int k = key(x)
        List<T> bucket = groups.getOr(k, [])
        bucket.push(x)
        groups.put(k, bucket)
    }
    return groups
}

                                              
                     
                       
                     

                              
                                
     

                                              

                                                     

                                                                

                    
                          
                        
         
                         
                   
     

              
                           
                       
         
                                  
     

               
                           
                       
         
                               
     

                                      
 

                                     
                     
                       
                     

                                              

                                                   

                        
                 
                                      
                                      
                        
             
                     
         
                 
     

                          
                               
                   
                               
                  
         
                         
                         
     

                   
                               
                  
                       
         
                               
     

                                
                               
                  
                           
         
                               
     

                        
                               
                  
                        
         
                           
                           
                   
     

                       
                                               
                 
                                      
                                     
                     
         
                  
     

                       
                                           
                 
                                      
                                     
                     
         
                  
     

                  
                         
                         
     
 

                                               
                   
                       
                     

                                              

                           
                  
                                   
                       
                                   
                                       
                            
                    
                        
             
         
                 
     

                     
                                  
                                                              
     

                          
                                  
                                                            
                               
                  
         
                              
                              
     

                   
                                  
                                                             
                       
         
                               
     

                                
                          
                      
                           
         
                
     

                        
                                  
                                                             
                        
         
                           
                           
                   
     

                       
                                               
                 
                                      
                                     
                     
         
                  
     

                  
                         
                         
     
 

                                        
                        
                     
                    

                                    
                        
     

                                              

                                                     

                             
                                
                                          
                             
     

                        
                     
                               
                                                              
                               
                     
                    
                     
             
         
     

                          
                                  
                    
                             
                         
                        
                                                                          
                        
             
                                                                          
                        
             
                          
                     
             
                              
                    
         
     

                    
                         
                                           
     

               
                           
                       
         
                               
     

              
                           
                       
         
                                
                                         
                                             
                              
                            
                            
         
                  
     

                                      
 
