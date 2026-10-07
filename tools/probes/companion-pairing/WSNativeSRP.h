/* Experimental native HAP SRP bridge. Not linked by the application build. */
#ifndef WS_NATIVE_SRP_H
#define WS_NATIVE_SRP_H
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif

typedef struct ws_srp ws_srp;
enum {
    WS_SRP_OK = 0, WS_SRP_STATE = 1, WS_SRP_INPUT = 2,
    WS_SRP_CRYPTO = 3, WS_SRP_PROOF = 4, WS_SRP_RANDOM = 5
};
/* Mandatory choice: no implicit resolution of the upstream M2 padding disagreement. */
enum { WS_SRP_ADK_PADDED_M2 = 1, WS_SRP_SRPTOOLS_MINIMAL_M2 = 2 };
ws_srp *ws_srp_new(int proof_convention);
void ws_srp_clear(ws_srp *context);
void ws_srp_free(ws_srp *context);
int ws_srp_begin(ws_srp *context, const uint8_t *pin, size_t pin_length,
                 uint8_t salt[16], uint8_t server_public[384]);
/* Every verify attempt consumes the session, including malformed input and wrong proof. */
int ws_srp_verify(ws_srp *context, const uint8_t *client_public, size_t public_length,
                  const uint8_t *client_proof, size_t proof_length,
                  uint8_t server_proof[64], uint8_t session_key[64]);

#ifdef WS_SRP_TESTING
/* Test-only injection/snapshots. These symbols are absent from the normal bridge object. */
typedef struct {
    uint8_t verifier[384], scrambling[64], premaster[384], key[64], expected_proof[64];
} ws_srp_test_trace;
int ws_srp_test_begin(ws_srp *context, const uint8_t *user, size_t user_length,
                      const uint8_t *pin, size_t pin_length, const uint8_t salt[16],
                      const uint8_t private_b[32], uint8_t server_public[384], ws_srp_test_trace *trace);
int ws_srp_test_verify(ws_srp *context, const uint8_t *client_public, size_t public_length,
                       const uint8_t *client_proof, size_t proof_length, uint8_t server_proof[64],
                       uint8_t session_key[64], ws_srp_test_trace *trace);
#endif
#ifdef __cplusplus
}
#endif
#endif
