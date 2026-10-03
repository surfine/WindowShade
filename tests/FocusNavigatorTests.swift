import Foundation


@main
struct FocusNavigatorTests {
    static func main() {
        var t = TestSuite("I9")

        func item(_ id:String,_ x:Double,_ y:Double,_ group:String="g",_ visible:Bool=true,_ enabled:Bool=true,_ screen:UInt32=1)->FocusNavigator.Item {
            .init(id:id,group:group,display:.init(value:screen),rect:.init(x:x,y:y,width:10,height:10),visible:visible,enabled:enabled)
        }
        let screen=WS2.DisplayID(value:1)
        let grid=[item("a",0,0),item("b",20,0),item("c",0,20),item("d",20,20)]
        t.section("I9-01", "规则网格左右上下 → 正确下一格，到边不绕回")
        var a=FocusNavigator()
        t.expect(a.move(from:"a",direction:.right,display:screen,items:grid) == .focused("b"),"向右")
        t.expect(a.move(from:"b",direction:.down,display:screen,items:grid) == .focused("d"),"向下")
        t.expect(a.move(from:"d",direction:.right,display:screen,items:grid) == .focused("d"),"边缘保持")
        t.expect(a.move(from:"d",direction:.up,display:screen,items:grid) == .focused("b"),"向上")
        t.section("I9-02", "参差行含洞、隐藏/禁用/其他屏 → 只找可见可用本屏格")
        let irregular=[item("a",0,0),item("x",15,0,"g",false),item("y",16,0,"g",true,false),item("foreign",17,0,"g",true,true,2),item("far",40,1),item("diagonal",20,20)]
        t.expect(a.move(from:"a",direction:.right,display:screen,items:irregular) == .focused("far"),"投影重叠优先于斜向近格")
        t.section("I9-03", "同组尚有右侧目标 → 不先跳进更近的别组")
        let groups=[item("a",0,0),item("same",80,0),item("other",20,0,"h")]
        t.expect(a.move(from:"a",direction:.right,display:screen,items:groups) == .focused("same"),"组内优先")
        t.section("I9-04", "离组再回组 → 回到该方向上仍可聚焦的记忆格")
        let groups2=[item("a",0,0,"left"),item("b",0,20,"left"),item("c",30,10,"right")]
        var b=FocusNavigator()
        _=b.move(from:"b",direction:.right,display:screen,items:groups2)
        t.expect(b.move(from:"c",direction:.left,display:screen,items:groups2) == .focused("b"),"回到上次 b")
        let removed=[item("a",0,0,"left"),item("c",30,10,"right")]
        t.expect(b.move(from:"c",direction:.left,display:screen,items:removed) == .focused("a"),"记忆格被删除时重算")
        t.section("I9-05", "空、一格、失去旧焦点 → none、留原处、按稳定顺序起步")
        t.expect(b.move(from:nil,direction:.left,display:screen,items:[]) == .none,"空数组")
        t.expect(b.move(from:"a",direction:.down,display:screen,items:[item("a",0,0)]) == .focused("a"),"单格")
        t.expect(b.move(from:"missing",direction:.right,display:screen,items:grid.reversed()) == .focused("a"),"按位置起步不看输入次序")
        t.section("I9-06", "重复 ID、无效矩形、超容量 → 报错，不猜一个")
        t.expect(b.move(from:"a",direction:.right,display:screen,items:[item("a",0,0),item("a",20,0)]) == .invalidInput,"重复 ID")
        let bad=FocusNavigator.Item(id:"z",group:"g",display:screen,rect:.init(x:.nan,y:0,width:10,height:10),visible:true,enabled:true)
        t.expect(b.move(from:nil,direction:.right,display:screen,items:[bad]) == .invalidInput,"非法数值")
        t.expect(b.move(from:nil,direction:.right,display:screen,items:(0..<513).map{item("\($0)",Double($0),0)}) == .invalidInput,"容量上限")
        t.section("I9-07", "对称距离、不同输入排序 → 用稳定 ID 决定，不抖动")
        let tie=[item("o",0,0),item("b",20,10),item("a",20,-10)]
        var results:Set<String>=[]
        for list in [tie,Array(tie.reversed()),[tie[1],tie[0],tie[2]]] {
            var n=FocusNavigator()
            if case .focused(let id)=n.move(from:"o",direction:.right,display:screen,items:list){results.insert(id)}
        }
        t.expect(results==["a"],"稳定 tie-break")

        t.section("I9-08", "投影只重叠一点与重叠整边 → 同组中选重叠更多的格")
        var overlap=FocusNavigator()
        let uneven=[item("origin",0,0),item("tiny",11,9),item("full",40,0)]
        t.expect(overlap.move(from:"origin",direction:.right,display:screen,items:uneven) == .focused("full"),"不把1点和10点重叠当成一样")
        t.finish()
    }
}
