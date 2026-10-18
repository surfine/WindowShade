"""Original test-only SRP arithmetic. Python pow is NOT a production constant-time crypto backend.
N/g from RFC 5054 Appendix A. Candidate HAP proof encoding is deliberately explicit.
All inputs/private values here are artificial; never use fixture keys for a real pairing.
"""
import hashlib
N_HEX = '''FFFFFFFF FFFFFFFF C90FDAA2 2168C234 C4C6628B 80DC1CD1 29024E08
8A67CC74 020BBEA6 3B139B22 514A0879 8E3404DD EF9519B3 CD3A431B
302B0A6D F25F1437 4FE1356D 6D51C245 E485B576 625E7EC6 F44C42E9
A637ED6B 0BFF5CB6 F406B7ED EE386BFB 5A899FA5 AE9F2411 7C4B1FE6
49286651 ECE45B3D C2007CB8 A163BF05 98DA4836 1C55D39A 69163FA8
FD24CF5F 83655D23 DCA3AD96 1C62F356 208552BB 9ED52907 7096966D
670C354E 4ABC9804 F1746C08 CA18217C 32905E46 2E36CE3B E39E772C
180E8603 9B2783A2 EC07A28F B5C55DF0 6F4C52C9 DE2BCBF6 95581718
3995497C EA956AE5 15D22618 98FA0510 15728E5A 8AAAC42D AD33170D
04507A33 A85521AB DF1CBA64 ECFB8504 58DBEF0A 8AEA7157 5D060C7D
B3970F85 A6E1E4C7 ABF5AE8C DB0933D7 1E8C94E0 4A25619D CEE3D226
1AD2EE6B F12FFA06 D98A0864 D8760273 3EC86A64 521F2B18 177B200C
BBE11757 7A615D6C 770988C0 BAD946E2 08E24FA0 74E5AB31 43DB5BFC
E0FD108E 4B82D120 A93AD2CA FFFFFFFF FFFFFFFF'''
N = int(''.join(N_HEX.split()), 16)
G = 5
WIDTH = 384

def minimal(x: int) -> bytes:
    if x < 0: raise ValueError('negative integer')
    return x.to_bytes(max(1, (x.bit_length()+7)//8), 'big')

def padded(x: int) -> bytes:
    return x.to_bytes(WIDTH, 'big')

def h(*parts: bytes) -> bytes:
    return hashlib.sha512(b''.join(parts)).digest()

def integer(value: bytes) -> int:
    return int.from_bytes(value, 'big')

def checked_public(value: int) -> int:
    if not 0 < value < N: raise ValueError('public key outside canonical group range')
    return value

def k_value() -> int: return integer(h(minimal(N), padded(G)))
def x_value(salt: bytes, pin: str) -> int: return integer(h(salt, h(b'Pair-Setup:' + pin.encode('ascii'))))

def proof(salt: bytes, a_public: int, b_public: int, shared_key: bytes) -> bytes:
    checked_public(a_public); checked_public(b_public)
    if len(salt) != 16 or len(shared_key) != 64: raise ValueError('bad length')
    xor = bytes(x ^ y for x, y in zip(h(minimal(N)), h(minimal(G))))
    return h(xor, h(b'Pair-Setup'), salt, minimal(a_public), minimal(b_public), shared_key)

def client(salt: bytes, b_public: int, pin: str='0123', private: int=0x123456789abcdef123456789abcdef123456789abcdef123456789abcdef12345):
    checked_public(b_public)
    if private <= 0: raise ValueError('private exponent')
    a_public = checked_public(pow(G, private, N))
    u = integer(h(padded(a_public), padded(b_public)))
    if not u: raise ValueError('zero scrambling parameter')
    x = x_value(salt, pin)
    shared = pow((b_public - k_value()*pow(G,x,N)) % N, private + u*x, N)
    key = h(minimal(shared))
    return a_public, proof(salt,a_public,b_public,key), key

def server(salt: bytes, a_public: int, pin: str='0123', private: int=0xabcdef123456789abcdef123456789abcdef123456789abcdef123456789abcde):
    checked_public(a_public)
    v = pow(G,x_value(salt,pin),N)
    b_public = checked_public((k_value()*v + pow(G,private,N)) % N)
    u = integer(h(padded(a_public),padded(b_public)))
    if not u: raise ValueError('zero scrambling parameter')
    shared = pow((a_public*pow(v,u,N)) % N,private,N)
    key = h(minimal(shared))
    expected = proof(salt,a_public,b_public,key)
    return b_public,expected,key,h(minimal(a_public),expected,key)
