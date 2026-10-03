import json,sys,time
for line in sys.stdin:
    data=json.loads(line)
    if data.get("method")=="hang": time.sleep(5); continue
    if data.get("method")=="exit": sys.exit(0)
    payload=json.dumps({"id": data.get("id"), "result": {"echo":data.get("params",{})}},separators=(",",":"))+"\n"
    # 故意拆成数段，检验流不是消息边界。
    for i in range(0,len(payload),3):
        sys.stdout.write(payload[i:i+3]);sys.stdout.flush()
