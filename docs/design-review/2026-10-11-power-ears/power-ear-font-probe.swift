import Cocoa
let font=NSFont.monospacedDigitSystemFont(ofSize:12,weight:.semibold)
let rounded=font.fontDescriptor.withDesign(.rounded).flatMap{NSFont(descriptor:$0,size:font.pointSize)} ?? font
for s in ["0%","5%","20%","21%","82%","100%"] {print(s,NSAttributedString(string:s,attributes:[.font:rounded]).size().width,"slot34 less12:",22)}
