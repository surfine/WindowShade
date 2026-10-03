import Foundation


@main
struct PresenceLockTests {
    static func main() {
        var t = TestSuite("L1")

        func ready(_ cfg:PresenceLock.Configuration = .init())->PresenceLock {
            var p=PresenceLock(configuration:cfg,bootID:fixtureBoot)
            _=p.handle(.enable,at:sec(0)); _=p.handle(.systemUnlocked,at:sec(0))
            _=p.handle(.connected(.phone,generation:1),at:sec(0))
            _=p.handle(.readStarted(.phone,generation:1,request:1),at:sec(0))
            _=p.handle(.readSucceeded(.phone,generation:1,request:1),at:sec(0.1)); return p
        }
        func prepared(_ effects:[PresenceLock.Effect])->WS2.Token? {
            effects.compactMap { if case .prepareCommit(let token)=$0{return token};return nil }.first
        }
        func returnToken(_ effects:[PresenceLock.Effect])->WS2.Token? {
            effects.compactMap { if case .requestReturnAuthorization(_,let attempt)=$0{return attempt};return nil }.first
        }
        t.section("L1-01", "成功读取后超过两秒未新读 → 仍在场；新读超时才离开")
        var a=ready(); _=a.handle(.tick,at:sec(5))
        t.expect(a.status(of:.phone) == .present && a.phase == .idle,"两秒是请求超时，不是 lastSeen 超时")
        _=a.handle(.readStarted(.phone,generation:1,request:2),at:sec(5))
        _=a.handle(.tick,at:sec(6.999)); t.expect(a.phase == .idle,"请求未超时")
        _=a.handle(.tick,at:sec(7)); t.expect(a.phase == .grace(deadline:sec(8.5),reason:.devices),"请求两秒后进入宽限")
        t.section("L1-02", "明确断开后 1.5+10 秒 → 先准备，commit 才依序收起/暂停/请求锁")
        var b=ready(); _=b.handle(.disconnected(.phone,generation:1),at:sec(1))
        t.expect(b.nextWake==sec(2.5),"静默宽限截止")
        let count=b.handle(.tick,at:sec(2.5)); t.expect(count.contains(.countdown(10,.devices)),"十秒倒数")
        let token=prepared(b.handle(.tick,at:sec(12.5)))!
        t.expect(b.ownedLock==nil,"准备不冒充已锁")
        t.expect(b.handle(.commitLock(token),at:sec(12.5)) == [.tuckPrivate(token),.pauseKnownMedia(token),.requestLock(token)],"固定动作顺序")
        _=b.handle(.lockConfirmed(token),at:sec(12.6)); t.expect(b.ownedLock==token && b.phase == .locked,"真实回执才归属自动锁")
        t.section("L1-03", "宽限内新代次重连，旧代次断线晚到 → 取消且不被旧事件复活")
        var c=ready(); _=c.handle(.disconnected(.phone,generation:1),at:sec(1))
        t.expect(c.handle(.connected(.phone,generation:2),at:sec(2)).contains(.cancelled),"重连取消")
        _=c.handle(.disconnected(.phone,generation:1),at:sec(2.1))
        t.expect(c.phase == .idle && c.status(of:.phone) == .connecting,"旧代次丢弃")
        _=c.handle(.readStarted(.phone,generation:2,request:1),at:sec(2.2)); _=c.handle(.readSucceeded(.phone,generation:2,request:1),at:sec(2.3))
        t.expect(c.status(of:.phone) == .present,"新读证实存活")
        t.section("L1-04", "倒数到点与用户输入同批 → 输入先取消；其后每次输入重置60秒静默期")
        var d=ready(); _=d.handle(.disconnected(.phone,generation:1),at:sec(1)); _=d.handle(.tick,at:sec(2.5))
        let race=d.handleBatch([.tick,.userInput],at:sec(12.5))
        t.expect(prepared(race)==nil && d.phase == .idle,"同批输入优先")
        _=d.handle(.userInput,at:sec(20)); _=d.handle(.tick,at:sec(79.999))
        t.expect(d.phase == .idle,"连续60秒从最后输入算")
        _=d.handle(.tick,at:sec(80)); t.expect(d.phase == .grace(deadline:sec(81.5),reason:.devices),"再从宽限开始，不立即锁")
        t.section("L1-05", "手机+手表，另一个未知或在场 → 不锁；两者明确离开才倒数")
        var cfg=PresenceLock.Configuration(); cfg.watchRequired=true
        var e=ready(cfg); _=e.handle(.disconnected(.phone,generation:1),at:sec(1))
        t.expect(e.phase == .idle,"未知手表不等于离开")
        _=e.handle(.connected(.watch,generation:1),at:sec(2)); _=e.handle(.disconnected(.watch,generation:1),at:sec(3))
        t.expect(e.phase == .grace(deadline:sec(4.5),reason:.devices),"两者都 away")
        t.section("L1-06", "极弱 RSSI 或蓝牙不可用 → 不据此判人离开")
        var f=ready(); _=f.handle(.rssi(generation:1,dbm:-120),at:sec(1))
        t.expect(f.phase == .idle,"RSSI 不锁")
        _=f.handle(.sensorUnavailable,at:sec(2)); _=f.handle(.disconnected(.phone,generation:1),at:sec(3)); _=f.handle(.tick,at:sec(30))
        t.expect(f.status(of:.phone) == .unknown && f.phase == .idle,"失能后的旧断线不触发")
        t.section("L1-07", "摄像头无首个健康有人帧或回调停了 → 不算人已离开")
        cfg=PresenceLock.Configuration();cfg.cameraEnabled=true
        var g=ready(cfg); _=g.handle(.cameraFrame(personPresent:false,healthy:true),at:sec(30)); _=g.handle(.tick,at:sec(90))
        t.expect(g.phase == .idle,"初始空画面不武断离开")
        _=g.handle(.cameraFrame(personPresent:true,healthy:true),at:sec(91))
        for i in 0...20 { _=g.handle(.cameraFrame(personPresent:false,healthy:true),at:sec(92+Double(i)/2)) }
        t.expect(g.phase == .grace(deadline:sec(103.5),reason:.camera),"健康连续缺人十秒才宽限")
        _=g.handle(.tick,at:sec(105)); t.expect(g.phase == .idle,"摄像头回调失效取消倒数")
        t.section("L1-08", "锁屏请求无实际回执或错误编号 → 不认定已锁，不建立返回资格")
        var h=ready(); _=h.handle(.disconnected(.phone,generation:1),at:sec(1)); let htoken=prepared(h.handle(.tick,at:sec(12.5)))!
        _=h.handle(.commitLock(htoken),at:sec(12.5)); _=h.handle(.lockConfirmed(.init(bootID:fixtureBoot,serial:999)),at:sec(12.6))
        t.expect(h.ownedLock==nil,"错编号不成立")
        t.expect(h.handle(.tick,at:sec(15.5)).contains(.fault(.missingDependency)) && h.ownedLock==nil,"三秒无回执只能未知")
        t.section("L1-09", "自己的锁+新连接读取+连续强RSSI → 仅请求现有身份授权，最多三次")
        cfg=PresenceLock.Configuration();cfg.returnEnabled=true
        var r=ready(cfg); _=r.handle(.disconnected(.phone,generation:1),at:sec(1));let owner=prepared(r.handle(.tick,at:sec(12.5)))!
        _=r.handle(.commitLock(owner),at:sec(12.5)); _=r.handle(.lockConfirmed(owner),at:sec(12.6))
        _=r.handle(.connected(.phone,generation:2),at:sec(13)); _=r.handle(.readStarted(.phone,generation:2,request:1),at:sec(13));_=r.handle(.readSucceeded(.phone,generation:2,request:1),at:sec(13.1))
        var attempts:[WS2.Token]=[]
        for round in 0..<4 {
            let start=14+Double(round)*3
            var result:[PresenceLock.Effect]=[]
            for i in 0...4 {result += r.handle(.rssi(generation:2,dbm:-50),at:sec(start+Double(i)/2))}
            if let token=returnToken(result){attempts.append(token);_=r.handle(.returnAttemptFinished(token),at:sec(start+2.1))}
        }
        t.expect(attempts.count==3 && r.returnAttempts==3 && Set(attempts).count==3,"三次不同请求编号，无解锁动作")
        let resumed=r.handle(.systemUnlocked,at:sec(30))
        t.expect(resumed==[.resumeOwnedMedia(owner)],"只恢复本次锁归属的媒体")
        t.expect(r.handle(.systemUnlocked,at:sec(31)).isEmpty,"解锁回执幂等")
        t.section("L1-10", "手动锁 → 不产生返回授权请求")
        var manual=ready(cfg); _=manual.handle(.systemLocked,at:sec(1)); var candidates=0
        for i in 0...8 {if returnToken(manual.handle(.rssi(generation:1,dbm:-40),at:sec(2+Double(i)/2))) != nil {candidates += 1}}
        t.expect(candidates==0 && manual.ownedLock==nil,"手动锁无资格")
        cfg.faceEnabled=false; var noFace=ready(cfg);_=noFace.handle(.systemLocked,at:sec(1))
        t.expect(returnToken(noFace.handle(.rssi(generation:1,dbm:-40),at:sec(4)))==nil,"手机单因素不开放")
        t.section("L1-11", "prepare后同批取消与commit、关闭后晚到锁回执 → 不锁或不授予归属")
        var k=ready(); _=k.handle(.disconnected(.phone,generation:1),at:sec(1));let kt=prepared(k.handle(.tick,at:sec(12.5)))!
        let cancelled=k.handleBatch([.commitLock(kt),.userInput],at:sec(12.5))
        t.expect(!cancelled.contains(.requestLock(kt)),"提交前最后取消点")
        var off=ready();_=off.handle(.disconnected(.phone,generation:1),at:sec(1));let ot=prepared(off.handle(.tick,at:sec(12.5)))!
        _=off.handle(.commitLock(ot),at:sec(12.5));_=off.handle(.disable,at:sec(12.6));_=off.handle(.lockConfirmed(ot),at:sec(12.7))
        t.expect(off.ownedLock==nil,"关闭后不能新获归属")
        t.section("L1-12", "时钟倒流、睡眠后旧回调 → 拒绝；唤醒等待真实锁态")
        t.expect(off.handle(.tick,at:sec(0)) == [.fault(.timeReversed)],"倒流拒绝")
        var asleep=ready();_=asleep.handle(.sleep,at:sec(1));_=asleep.handle(.wake,at:sec(2));_=asleep.handle(.disconnected(.phone,generation:1),at:sec(3));_=asleep.handle(.tick,at:sec(99))
        t.expect(asleep.phase == .idle && asleep.lockState == .unknown,"睡醒不能用旧证据锁或开")

        t.section("L1-13", "自己的锁但仍是旧连接、刷脸关闭或RSSI恰为-60 → 都不产生返回授权")
        func owned(_ config:PresenceLock.Configuration)->PresenceLock {
            var value=ready(config);_=value.handle(.disconnected(.phone,generation:1),at:sec(1))
            let tok=prepared(value.handle(.tick,at:sec(12.5)))!;_=value.handle(.commitLock(tok),at:sec(12.5));_=value.handle(.lockConfirmed(tok),at:sec(12.6))
            return value
        }
        func rejoin(_ value:inout PresenceLock) {
            _=value.handle(.connected(.phone,generation:2),at:sec(13));_=value.handle(.readStarted(.phone,generation:2,request:1),at:sec(13));_=value.handle(.readSucceeded(.phone,generation:2,request:1),at:sec(13.1))
        }
        cfg=PresenceLock.Configuration();cfg.returnEnabled=true
        var oldLink=owned(cfg);var oldEffects:[PresenceLock.Effect]=[]
        for i in 0...6 {oldEffects += oldLink.handle(.rssi(generation:1,dbm:-40),at:sec(14+Double(i)/2))}
        t.expect(returnToken(oldEffects)==nil,"旧连接即便强信号也没有返回资格")
        var boundary=owned(cfg);rejoin(&boundary);var boundaryEffects:[PresenceLock.Effect]=[]
        for i in 0...6 {boundaryEffects += boundary.handle(.rssi(generation:2,dbm:-60),at:sec(14+Double(i)/2))}
        t.expect(returnToken(boundaryEffects)==nil,"等于阈值不算大于阈值")
        cfg.faceEnabled=false;var faceOff=owned(cfg);rejoin(&faceOff);var faceEffects:[PresenceLock.Effect]=[]
        for i in 0...6 {faceEffects += faceOff.handle(.rssi(generation:2,dbm:-40),at:sec(14+Double(i)/2))}
        t.expect(returnToken(faceEffects)==nil,"确实有本次锁归属和新连接，但不开放手机单因素")
        t.section("L1-14", "强RSSI中途出现NaN → 连续时长重算，不沿用坏样本前的积累")
        cfg.faceEnabled=true;var invalid=owned(cfg);rejoin(&invalid)
        for i in 0...3 {_=invalid.handle(.rssi(generation:2,dbm:-40),at:sec(14+Double(i)/2))}
        _=invalid.handle(.rssi(generation:2,dbm:.nan),at:sec(15.75))
        t.expect(returnToken(invalid.handle(.rssi(generation:2,dbm:-40),at:sec(16)))==nil,"无效样本打断两秒连续性")
        var validEffects:[PresenceLock.Effect]=[]
        for i in 1...4 {validEffects += invalid.handle(.rssi(generation:2,dbm:-40),at:sec(16+Double(i)/2))}
        t.expect(returnToken(validEffects) != nil,"重新连续两秒后才形成候选")
        t.finish()
    }
}
