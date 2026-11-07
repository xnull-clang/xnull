protocol Shape { Int area(); }
class Sq implements Shape { Int area() { return 1 } }
static Int main() { Sq s = new Sq(); print(s is Shape); return 0 }
