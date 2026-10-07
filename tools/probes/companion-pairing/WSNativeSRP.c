/*
 * Based on the HAP SRP-3072/SHA-512 behavior in Apple HomeKitADK:
 * Copyright (c) 2015-2019 The HomeKit ADK Contributors.
 * Licensed under Apache License 2.0; see LICENSE-HomeKitADK.txt.
 * Reference commit: fb201f98f5fdc7fef6a455054f08b59cca5d1ec8.
 *
 * Modifications, 2026-10-07: isolated session API, fixed RFC 5054 group,
 * public BN/EVP only (no deprecated SRP API), explicit constant-time modular
 * exponentiation, recoverable errors, one-shot verification, secret cleanup,
 * explicit M2 convention, and compile-gated deterministic test hooks.
 * This probe is NOT a distributable or security-qualified app component.
 */
#include "WSNativeSRP.h"
#include <openssl/bn.h>
#include <openssl/crypto.h>
#include <openssl/evp.h>
#include <openssl/rand.h>
#include <string.h>

/* RFC 5054 Appendix A, 3072-bit MODP group, generator 5. */
static const char PRIME_HEX[] =
    "FFFFFFFFFFFFFFFFC90FDAA22168C234C4C6628B80DC1CD129024E088A67CC74"
    "020BBEA63B139B22514A08798E3404DDEF9519B3CD3A431B302B0A6DF25F1437"
    "4FE1356D6D51C245E485B576625E7EC6F44C42E9A637ED6B0BFF5CB6F406B7ED"
    "EE386BFB5A899FA5AE9F24117C4B1FE649286651ECE45B3DC2007CB8A163BF05"
    "98DA48361C55D39A69163FA8FD24CF5F83655D23DCA3AD961C62F356208552BB"
    "9ED529077096966D670C354E4ABC9804F1746C08CA18217C32905E462E36CE3B"
    "E39E772C180E86039B2783A2EC07A28FB5C55DF06F4C52C9DE2BCBF695581718"
    "3995497CEA956AE515D2261898FA051015728E5A8AAAC42DAD33170D04507A33"
    "A85521ABDF1CBA64ECFB850458DBEF0A8AEA71575D060C7DB3970F85A6E1E4C7"
    "ABF5AE8CDB0933D71E8C94E04A25619DCEE3D2261AD2EE6BF12FFA06D98A0864"
    "D87602733EC86A64521F2B18177B200CBBE117577A615D6C770988C0BAD946E2"
    "08E24FA074E5AB3143DB5BFCE0FD108E4B82D120A93AD2CAFFFFFFFFFFFFFFFF";

struct ws_srp {
    BIGNUM *N, *g, *b, *v, *B;
    uint8_t salt[16], user[128];
    size_t user_length;
    int phase; /* 0=fresh, 1=started, 2=consumed */
    int convention;
};
#ifndef WS_SRP_TESTING
typedef struct {
    uint8_t verifier[384], scrambling[64], premaster[384], key[64], expected_proof[64];
} ws_srp_test_trace;
#endif

typedef struct { const uint8_t *data; size_t length; } part;
static int hash_parts(uint8_t output[64], const part *parts, size_t count) {
    EVP_MD_CTX *hash = EVP_MD_CTX_new();
    int ok = 0;
    unsigned length = 0;
    if (!hash || EVP_DigestInit_ex(hash, EVP_sha512(), NULL) != 1) goto done;
    for (size_t i = 0; i < count; ++i) {
        if ((parts[i].length && !parts[i].data) ||
            EVP_DigestUpdate(hash, parts[i].data, parts[i].length) != 1) goto done;
    }
    if (EVP_DigestFinal_ex(hash, output, &length) == 1 && length == 64) ok = 1;
done:
    EVP_MD_CTX_free(hash);
    if (!ok) OPENSSL_cleanse(output, 64);
    return ok;
}
static size_t zeros(const uint8_t *data, size_t length) {
    size_t i = 0;
    while (i < length && data[i] == 0) ++i;
    return i;
}
static void secrets_clear(ws_srp *c) {
    BN_clear_free(c->b); c->b = NULL;
    BN_clear_free(c->v); c->v = NULL;
    BN_clear_free(c->B); c->B = NULL;
    OPENSSL_cleanse(c->salt, sizeof c->salt);
    OPENSSL_cleanse(c->user, sizeof c->user);
    c->user_length = 0;
}
void ws_srp_clear(ws_srp *c) {
    if (!c) return;
    c->phase = 2;
    secrets_clear(c);
}
void ws_srp_free(ws_srp *c) {
    if (!c) return;
    ws_srp_clear(c);
    BN_clear_free(c->N); BN_clear_free(c->g);
    OPENSSL_clear_free(c, sizeof *c);
}
ws_srp *ws_srp_new(int convention) {
    if (convention != WS_SRP_ADK_PADDED_M2 && convention != WS_SRP_SRPTOOLS_MINIMAL_M2) return NULL;
    ws_srp *c = OPENSSL_zalloc(sizeof *c);
    if (!c) return NULL;
    c->convention = convention;
    c->g = BN_new();
    if (!c->g || !BN_hex2bn(&c->N, PRIME_HEX) || BN_num_bits(c->N) != 3072 || !BN_set_word(c->g, 5)) {
        ws_srp_free(c); return NULL;
    }
    return c;
}

static int begin_fixed(ws_srp *c, const uint8_t *user, size_t user_length,
                       const uint8_t *pin, size_t pin_length, const uint8_t salt[16],
                       const uint8_t private_b[32], uint8_t public_b[384], ws_srp_test_trace *trace) {
    int status = WS_SRP_CRYPTO;
    uint8_t inner[64] = {0}, x_bytes[64] = {0}, k_bytes[64] = {0};
    uint8_t n_pad[384] = {0}, g_pad[384] = {0};
    BN_CTX *ctx = NULL;
    BIGNUM *x = NULL, *k = NULL, *gb = NULL, *kv = NULL;
    if (public_b) memset(public_b, 0, 384);
    if (!c) return WS_SRP_STATE;
    if (c->phase != 0) { ws_srp_clear(c); return WS_SRP_STATE; }
    c->phase = 2;
    if (!user || !user_length || user_length > 128 || !pin || !pin_length || pin_length > 64 ||
        !salt || !private_b || !public_b) { status = WS_SRP_INPUT; goto done; }
    memcpy(c->user, user, user_length); c->user_length = user_length;
    memcpy(c->salt, salt, 16);
    const uint8_t colon = ':';
    part inner_parts[] = {{user, user_length}, {&colon, 1}, {pin, pin_length}};
    if (!hash_parts(inner, inner_parts, 3)) goto done;
    part x_parts[] = {{salt, 16}, {inner, 64}};
    if (!hash_parts(x_bytes, x_parts, 2)) goto done;
    ctx = BN_CTX_secure_new(); x = BN_secure_new(); k = BN_new();
    gb = BN_secure_new(); kv = BN_secure_new();
    c->b = BN_secure_new(); c->v = BN_secure_new(); c->B = BN_new();
    if (!ctx || !x || !k || !gb || !kv || !c->b || !c->v || !c->B ||
        !BN_bin2bn(x_bytes, 64, x) || !BN_bin2bn(private_b, 32, c->b) || BN_is_zero(c->b)) goto done;
    BN_set_flags(x, BN_FLG_CONSTTIME); BN_set_flags(c->b, BN_FLG_CONSTTIME);
    if (!BN_mod_exp_mont_consttime(c->v, c->g, x, c->N, ctx, NULL) ||
        !BN_mod_exp_mont_consttime(gb, c->g, c->b, c->N, ctx, NULL) ||
        BN_bn2binpad(c->N, n_pad, 384) != 384 || BN_bn2binpad(c->g, g_pad, 384) != 384) goto done;
    part k_parts[] = {{n_pad, 384}, {g_pad, 384}};
    if (!hash_parts(k_bytes, k_parts, 2) || !BN_bin2bn(k_bytes, 64, k) ||
        !BN_mod_mul(kv, k, c->v, c->N, ctx) || !BN_mod_add(c->B, kv, gb, c->N, ctx) ||
        BN_is_zero(c->B) || BN_bn2binpad(c->B, public_b, 384) != 384) goto done;
    if (trace && BN_bn2binpad(c->v, trace->verifier, 384) != 384) goto done;
    c->phase = 1; status = WS_SRP_OK;
done:
    BN_clear_free(x); BN_clear_free(k); BN_clear_free(gb); BN_clear_free(kv); BN_CTX_free(ctx);
    OPENSSL_cleanse(inner, sizeof inner); OPENSSL_cleanse(x_bytes, sizeof x_bytes);
    OPENSSL_cleanse(k_bytes, sizeof k_bytes);
    if (status != WS_SRP_OK) { if (public_b) memset(public_b, 0, 384); ws_srp_clear(c); }
    return status;
}
int ws_srp_begin(ws_srp *c, const uint8_t *pin, size_t pin_length, uint8_t salt[16], uint8_t public_b[384]) {
    uint8_t random_salt[16] = {0}, random_b[32] = {0};
    int status;
    if (salt) memset(salt, 0, 16);
    if (public_b) memset(public_b, 0, 384);
    if (!c) return WS_SRP_STATE;
    if (c->phase != 0) { ws_srp_clear(c); return WS_SRP_STATE; }
    if (!salt || !public_b || !pin || !pin_length || pin_length > 64) { ws_srp_clear(c); return WS_SRP_INPUT; }
    if (RAND_priv_bytes(random_salt, 16) != 1 || RAND_priv_bytes(random_b, 32) != 1) {
        status = WS_SRP_RANDOM; ws_srp_clear(c);
    } else {
        static const uint8_t user[] = "Pair-Setup";
        status = begin_fixed(c, user, sizeof user - 1, pin, pin_length, random_salt, random_b, public_b, NULL);
        if (status == WS_SRP_OK) memcpy(salt, random_salt, 16);
    }
    OPENSSL_cleanse(random_salt, sizeof random_salt); OPENSSL_cleanse(random_b, sizeof random_b);
    return status;
}

static int verify_inner(ws_srp *c, const uint8_t *client_public, size_t public_length,
                        const uint8_t *proof, size_t proof_length, uint8_t m2[64], uint8_t key[64],
                        ws_srp_test_trace *trace) {
    int status = WS_SRP_CRYPTO;
    BN_CTX *ctx = NULL;
    BIGNUM *A = NULL, *u = NULL, *vu = NULL, *base = NULL, *S = NULL;
    uint8_t a_pad[384] = {0}, b_pad[384] = {0}, n_pad[384] = {0}, s_pad[384] = {0};
    uint8_t u_bytes[64] = {0}, K[64] = {0}, hn[64] = {0}, hg[64] = {0}, hu[64] = {0}, expected[64] = {0};
    if (m2) memset(m2, 0, 64);
    if (key) memset(key, 0, 64);
    if (!c) return WS_SRP_STATE;
    if (c->phase != 1) { ws_srp_clear(c); return WS_SRP_STATE; }
    c->phase = 2; /* Consume before validating any attacker-controlled input. */
    if (!client_public || !public_length || public_length > 384 || !proof || proof_length != 64 || !m2 || !key) {
        status = WS_SRP_INPUT; goto done;
    }
    ctx = BN_CTX_secure_new(); A = BN_new(); u = BN_new();
    vu = BN_secure_new(); base = BN_secure_new(); S = BN_secure_new();
    if (!ctx || !A || !u || !vu || !base || !S || !BN_bin2bn(client_public, (int)public_length, A)) goto done;
    if (BN_is_zero(A) || BN_cmp(A, c->N) >= 0) { status = WS_SRP_INPUT; goto done; }
    if (BN_bn2binpad(A, a_pad, 384) != 384 || BN_bn2binpad(c->B, b_pad, 384) != 384 ||
        BN_bn2binpad(c->N, n_pad, 384) != 384) goto done;
    part u_parts[] = {{a_pad, 384}, {b_pad, 384}};
    if (!hash_parts(u_bytes, u_parts, 2) || !BN_bin2bn(u_bytes, 64, u) || BN_is_zero(u)) goto done;
    BN_set_flags(u, BN_FLG_CONSTTIME);
    if (!BN_mod_exp_mont_consttime(vu, c->v, u, c->N, ctx, NULL) ||
        !BN_mod_mul(base, A, vu, c->N, ctx) ||
        !BN_mod_exp_mont_consttime(S, base, c->b, c->N, ctx, NULL) || BN_is_zero(S) ||
        BN_bn2binpad(S, s_pad, 384) != 384) goto done;
    size_t z_s = zeros(s_pad, 384), z_a = zeros(a_pad, 384), z_b = zeros(b_pad, 384);
    part key_parts[] = {{s_pad + z_s, 384 - z_s}};
    const uint8_t generator = 5;
    part hn_parts[] = {{n_pad, 384}}, hg_parts[] = {{&generator, 1}}, hu_parts[] = {{c->user, c->user_length}};
    if (!hash_parts(K, key_parts, 1) || !hash_parts(hn, hn_parts, 1) ||
        !hash_parts(hg, hg_parts, 1) || !hash_parts(hu, hu_parts, 1)) goto done;
    for (size_t i = 0; i < 64; ++i) hn[i] ^= hg[i];
    part proof_parts[] = {{hn, 64}, {hu, 64}, {c->salt, 16}, {a_pad + z_a, 384 - z_a},
                          {b_pad + z_b, 384 - z_b}, {K, 64}};
    if (!hash_parts(expected, proof_parts, 6)) goto done;
    if (trace) {
        memcpy(trace->scrambling, u_bytes, 64); memcpy(trace->premaster, s_pad, 384);
        memcpy(trace->key, K, 64); memcpy(trace->expected_proof, expected, 64);
    }
    if (CRYPTO_memcmp(expected, proof, 64) != 0) { status = WS_SRP_PROOF; goto done; }
    size_t m2_offset = c->convention == WS_SRP_ADK_PADDED_M2 ? 0 : z_a;
    part m2_parts[] = {{a_pad + m2_offset, 384 - m2_offset}, {expected, 64}, {K, 64}};
    if (!hash_parts(m2, m2_parts, 3)) goto done;
    memcpy(key, K, 64); status = WS_SRP_OK;
done:
    BN_clear_free(A); BN_clear_free(u); BN_clear_free(vu); BN_clear_free(base); BN_clear_free(S); BN_CTX_free(ctx);
    OPENSSL_cleanse(s_pad, sizeof s_pad); OPENSSL_cleanse(K, sizeof K);
    OPENSSL_cleanse(expected, sizeof expected); OPENSSL_cleanse(u_bytes, sizeof u_bytes);
    OPENSSL_cleanse(hu, sizeof hu); OPENSSL_cleanse(hn, sizeof hn); OPENSSL_cleanse(hg, sizeof hg);
    ws_srp_clear(c);
    if (status != WS_SRP_OK) { if (m2) memset(m2, 0, 64); if (key) memset(key, 0, 64); }
    return status;
}
int ws_srp_verify(ws_srp *c, const uint8_t *A, size_t A_length, const uint8_t *proof, size_t proof_length,
                  uint8_t m2[64], uint8_t key[64]) {
    return verify_inner(c, A, A_length, proof, proof_length, m2, key, NULL);
}
#ifdef WS_SRP_TESTING
int ws_srp_test_begin(ws_srp *c, const uint8_t *user, size_t user_length, const uint8_t *pin, size_t pin_length,
                      const uint8_t salt[16], const uint8_t b[32], uint8_t B[384], ws_srp_test_trace *trace) {
    return begin_fixed(c, user, user_length, pin, pin_length, salt, b, B, trace);
}
int ws_srp_test_verify(ws_srp *c, const uint8_t *A, size_t length, const uint8_t *proof, size_t proof_length,
                       uint8_t m2[64], uint8_t key[64], ws_srp_test_trace *trace) {
    return verify_inner(c, A, length, proof, proof_length, m2, key, trace);
}
#endif
