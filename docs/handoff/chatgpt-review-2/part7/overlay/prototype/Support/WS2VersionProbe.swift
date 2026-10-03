import Foundation

/// Real --version process, bounded output and an absolute deadline, then native reaping.
@MainActor final class WS2VersionProbe {
    private(set) var launched=false
    private(set) var reaped=false
    var onReaped:(()->Void)?
    private var channel:WS2DuplexProcess!
    private var timeout:Task<Void,Never>?
    private var output=Data()
    private var invalid=false
    private var completion:((Bool)->Void)?
    init(profile:WS2LocalLaunchProfile,mayContinue:@escaping()->Bool,completion:@escaping(Bool)->Void) throws {
        self.completion=completion
        channel=try WS2DuplexProcess(executable:profile.executable,arguments:["--version"],workingDirectory:profile.root,
            environment:profile.environment,mayWrite:mayContinue)
        channel.onLine={ [weak self] line in
            guard let self else { return }
            guard mayContinue(),self.output.count+line.count+1<=8192 else { self.invalid=true;self.channel.stop();return }
            self.output.append(line);self.output.append(10)
        }
        channel.onEnd={ [weak self] reason in
            guard let self else { return }
            if reason != .eof && reason != .processExit { self.invalid=true }
        }
        channel.onReaped={ [weak self] fact in
            guard let self else { return }
            self.reaped=true
            let receipt=self.onReaped;self.onReaped=nil
            let ok = !self.invalid && !fact.wasSignalled && fact.status==0 && mayContinue() &&
                String(data:self.output,encoding:.utf8)?.trimmingCharacters(in:.whitespacesAndNewlines)=="codex-cli 0.153.0"
            self.finish(ok);receipt?()
        }
    }
    func start() throws {
        do { try channel.start();launched=true } catch { finish(false);throw error }
        timeout=Task { [weak self] in
            do { try await Task.sleep(nanoseconds:4_000_000_000) } catch { return }
            guard let self else { return };self.invalid=true;self.channel.stop()
            // Retain the pending probe until its own child is reaped; timeout is not an exit receipt.
        }
    }
    func cancel() { invalid=true;channel.stop();finish(false) }
    private func finish(_ ok:Bool) {
        timeout?.cancel();timeout=nil
        let callback=completion;completion=nil;output.removeAll(keepingCapacity:false);callback?(ok)
    }
}
