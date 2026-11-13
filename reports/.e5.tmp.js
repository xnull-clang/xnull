   {t:"xdk.embedded（嵌入式 · 对标 Arduino/mbed + Rust embedded-hal）",s:"todo",c:[
     {t:"GPIO",s:"todo",c:[
       {t:"pinMode(pin,mode)/digitalRead(pin)/digitalWrite(pin,v)",s:"todo"},
       {t:"analogRead(pin)/analogWrite(pin,v)（PWM）",s:"todo"},
       {t:"attachInterrupt(pin,mode,handler)",s:"todo"}
     ]},
     {t:"串口 UART",s:"todo",c:[
       {t:"Uart.open(port,baud)/read/write/readLine",s:"todo"},
       {t:"Uart.close()/available()",s:"todo"}
     ]},
     {t:"I2C / SPI",s:"todo",c:[
       {t:"I2c.open(bus)/writeReg(addr,reg,v)/readReg(addr,reg)",s:"todo"},
       {t:"Spi.open(dev)/transfer(tx)→Bytes/setMode/setSpeed",s:"todo"}
     ]},
     {t:"寄存器与板级",s:"todo",c:[
       {t:"readReg(addr)/writeReg(addr,v)/bitSet/bitClear",s:"todo"},
       {t:"delay(ms)/delayMicros(us)/millis()/micros()",s:"todo"},
       {t:"watchdogEnable/reset/boardInfo()",s:"todo"}
     ]},
     {t:"FFI 绑定面",s:"todo",c:[
       {t:"hal.bind(driver)/layout(c) 寄存器布局验证",s:"todo",d:"复用 FFI 租约与布局合同"}
     ]}
   ]},
   {t:"xdk.image（图片处理 · 对标 Python Pillow + Go image）",s:"todo",c:[
     {t:"编解码",s:"todo",c:[
       {t:"decodePng(b)/decodeJpeg(b)/decodeGif(b)/decodeBmp(b)→Result<Image,Error>",s:"todo"},
       {t:"encodePng(img)/encodeJpeg(img,quality)→Bytes",s:"todo"},
       {t:"Image.open(path)/save(path)",s:"todo"}
     ]},
     {t:"像素访问",s:"todo",c:[
       {t:"width()/height()/format()/channels()",s:"todo"},
       {t:"getPixel(x,y)→Rgba/setPixel(x,y,c)",s:"todo"},
       {t:"Rgba.r/g/b/a；Rgba.fromHex(s)",s:"todo"}
     ]},
     {t:"几何变换",s:"todo",c:[
       {t:"resize(w,h)/thumbnail(size)/crop(rect)",s:"todo"},
       {t:"rotate90/rotate180/rotate(deg)/flipH/flipV",s:"todo"}
     ]},
     {t:"颜色与滤镜",s:"todo",c:[
       {t:"grayscale()/brightness(k)/contrast(k)/saturation(k)",s:"todo"},
       {t:"blur(radius)/sharpen()/invert()/sepia()",s:"todo"}
     ]},
     {t:"绘制",s:"todo",c:[
       {t:"fillRect(rect,color)/drawLine/drawCircle/drawText",s:"todo"},
       {t:"histogram()→通道直方图",s:"todo"}
     ]}
   ]},
