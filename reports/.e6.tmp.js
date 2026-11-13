   {t:"xdk.vision（基础视觉 · 对标 OpenCV 基础面）",s:"todo",c:[
     {t:"灰度与二值化",s:"todo",c:[
       {t:"rgb2gray(img)/threshold(img,t)/adaptiveThreshold(img)",s:"todo"},
       {t:"otsuThreshold(img)→Int",s:"todo"}
     ]},
     {t:"滤波",s:"todo",c:[
       {t:"gaussianBlur(img,ksize)/medianBlur/boxBlur",s:"todo"},
       {t:"bilateralFilter(img)/sharpenKernel",s:"todo"}
     ]},
     {t:"边缘与形态学",s:"todo",c:[
       {t:"sobel(img,dx,dy)/canny(img,lo,hi)/laplacian(img)",s:"todo"},
       {t:"erode(img,k)/dilate(img,k)/morphOpen/morphClose",s:"todo"}
     ]},
     {t:"连通域与轮廓",s:"todo",c:[
       {t:"connectedComponents(img)→labels/stats/centroids",s:"todo"},
       {t:"findContours(img)→List<Contour>",s:"todo"},
       {t:"contourArea(c)/boundingRect(c)/arcLength(c)",s:"todo"}
     ]},
     {t:"颜色空间与匹配",s:"todo",c:[
       {t:"rgb2hsv/hsv2rgb/inRange(img,lo,hi)",s:"todo"},
       {t:"matchTemplate(img,tpl)→Result/归一化相关系数",s:"todo"},
       {t:"houghLines(img)/houghCircles(img)",s:"todo"}
     ]}
   ]},
   {t:"xdk.physics（物理 · 对标 Python pint/sympy 物理面）",s:"todo",c:[
     {t:"物理常量",s:"todo",c:[
       {t:"G 重力加速度 / C 光速 / G_CONST 万有引力",s:"todo"},
       {t:"KB 玻尔兹曼 / H 普朗克 / NA 阿伏伽德罗 / E_CHARGE 元电荷",s:"todo"}
     ]},
     {t:"运动学与力学",s:"todo",c:[
       {t:"displacement(v0,a,t)/finalVelocity(v0,a,t)",s:"todo"},
       {t:"force(m,a)/work(f,d)/kineticEnergy(m,v)/potentialEnergy(m,h)",s:"todo"},
       {t:"momentum(m,v)/impulse(f,t)/projectileRange(v,angle)",s:"todo"}
     ]},
     {t:"电路",s:"todo",c:[
       {t:"ohmsLaw(v?,i?,r?)/electricPower(v,i)",s:"todo"},
       {t:"seriesResistance(rs)/parallelResistance(rs)",s:"todo"}
     ]},
     {t:"热学与波动",s:"todo",c:[
       {t:"heatQ(m,c,dT)/idealGas(n,r,t)",s:"todo"},
       {t:"waveSpeed(freq,wavelength)/doppler(f,v,vs)",s:"todo"}
     ]},
     {t:"单位换算",s:"todo",c:[
       {t:"m2ft/ft2m/kg2lb/lb2kg/celsius2fahrenheit/kmh2ms",s:"todo"},
       {t:"Unit.parse('9.8 m/s^2')→Quantity",s:"todo"}
     ]}
   ]},
