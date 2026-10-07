"""Small independent Python OPACK client codec; no production Swift codec is called."""
import struct
import uuid

class RawTime(int):
    pass

def pack(value):
    if value is None: return b'\x04'
    if value is True: return b'\x01'
    if value is False: return b'\x02'
    if isinstance(value, uuid.UUID): return b'\x05'+value.bytes
    if isinstance(value, RawTime): return b'\x06'+int(value).to_bytes(8,'little')
    if isinstance(value, int):
        assert 0 <= value < 2**64
        if value < 40: return bytes([value+8])
        for index,width in enumerate((1,2,4,8)):
            if value < 1<<(width*8): return bytes([0x30+index])+value.to_bytes(width,'little')
    if isinstance(value,float): return b'\x36'+struct.pack('<d',value)
    if isinstance(value,(str,bytes)):
        raw=value.encode() if isinstance(value,str) else value
        small,large=(0x40,0x61) if isinstance(value,str) else (0x70,0x91)
        if len(raw)<=32:return bytes([small+len(raw)])+raw
        width=1 if len(raw)<256 else 2
        return bytes([large+width-1])+len(raw).to_bytes(width,'little')+raw
    if isinstance(value,list):
        return bytes([0xd0+min(15,len(value))])+b''.join(pack(v) for v in value)+(b'\x03' if len(value)>=15 else b'')
    if isinstance(value,dict):
        return bytes([0xe0+min(15,len(value))])+b''.join(pack(k)+pack(v) for k,v in value.items())+(b'\x03' if len(value)>=15 else b'')
    raise TypeError(type(value))

def unpack(data):
    offset=0
    def take(n):
        nonlocal offset
        assert offset+n<=len(data)
        value=data[offset:offset+n];offset+=n;return value
    def read():
        tag=take(1)[0]
        if tag==1:return True
        if tag==2:return False
        if tag==4:return None
        if tag==5:return uuid.UUID(bytes=take(16))
        if tag==6:return RawTime(int.from_bytes(take(8),'little'))
        if 8<=tag<=0x2f:return tag-8
        if 0x30<=tag<=0x33:return int.from_bytes(take(1<<(tag-0x30)),'little')
        if tag==0x35:return struct.unpack('<f',take(4))[0]
        if tag==0x36:return struct.unpack('<d',take(8))[0]
        if 0x40<=tag<=0x64:
            n=tag-0x40 if tag<=0x60 else int.from_bytes(take(tag-0x60),'little')
            return take(n).decode()
        if 0x70<=tag<=0x94:
            n=tag-0x70 if tag<=0x90 else int.from_bytes(take(1<<(tag-0x91)),'little')
            return take(n)
        if 0xd0<=tag<=0xdf:
            n=tag&15; out=[]
            while (data[offset]!=3 if n==15 else len(out)<n):out.append(read())
            if n==15:take(1)
            return out
        if 0xe0<=tag<=0xff:
            n=tag&15; out={}
            while (data[offset]!=3 if n==15 else len(out)<n):
                key=read();assert isinstance(key,str) and key not in out;out[key]=read()
            if n==15:take(1)
            return out
        raise ValueError('unsupported test-oracle tag '+hex(tag))
    result=read();assert offset==len(data);return result
