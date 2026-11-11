//! Skein-MAC-512-256, which IHP's session cookies are signed with (the
//! clientsession library's `skeinMAC'`). RustCrypto's skein crate hashes
//! but takes no key, so this is Skein 1.3's UBI chaining over its
//! Threefish-512, with the key block first.

use threefish::Threefish512;

const BLOCK: usize = 64;

// Block types, from the Skein paper's table 6
const KEY: u64 = 0;
const CONFIG: u64 = 4;
const MESSAGE: u64 = 48;
const OUTPUT: u64 = 63;

/// One UBI pass: `state` chained over `message`, in 64-byte blocks, the last
/// padded with zeros (an empty message is one zero block)
fn ubi(state: [u64; 8], message: &[u8], block_type: u64) -> [u64; 8] {
    let mut state = state;
    let blocks = message.len().div_ceil(BLOCK).max(1);
    for i in 0..blocks {
        let start = i * BLOCK;
        let end = message.len().min(start + BLOCK);
        let mut bytes = [0u8; BLOCK];
        bytes[..end - start].copy_from_slice(&message[start..end]);
        let mut words = [0u64; 8];
        for (word, chunk) in words.iter_mut().zip(bytes.as_chunks::<8>().0) {
            *word = u64::from_le_bytes(*chunk);
        }
        let mut tweak1 = block_type << 56;
        if i == 0 {
            tweak1 |= 1 << 62;
        }
        if i == blocks - 1 {
            tweak1 |= 1 << 63;
        }
        // The bytes processed so far, this block's included
        let tweak = [end as u64, tweak1];
        let mut out = words;
        Threefish512::new_with_tweak_u64(&state, &tweak).encrypt_block_u64(&mut out);
        for (s, (o, w)) in state.iter_mut().zip(out.iter().zip(words)) {
            *s = o ^ w;
        }
    }
    state
}

/// Skein-512 with a 256-bit output, keyed with `key` (unkeyed if empty)
pub fn mac_512_256(key: &[u8], message: &[u8]) -> [u8; 32] {
    let state = if key.is_empty() {
        [0; 8]
    } else {
        ubi([0; 8], key, KEY)
    };
    // "SHA3", version 1, the output's length in bits, no tree
    let mut config = [0u8; 32];
    config[..4].copy_from_slice(b"SHA3");
    config[4..6].copy_from_slice(&1u16.to_le_bytes());
    config[8..16].copy_from_slice(&256u64.to_le_bytes());
    let state = ubi(state, &config, CONFIG);
    let state = ubi(state, message, MESSAGE);
    let state = ubi(state, &0u64.to_le_bytes(), OUTPUT);
    let mut out = [0u8; 32];
    for (chunk, word) in out.as_chunks_mut::<8>().0.iter_mut().zip(state) {
        chunk.copy_from_slice(&word.to_le_bytes());
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use ::skein::Digest;

    fn hex(bytes: &[u8]) -> String {
        bytes.iter().map(|b| format!("{b:02x}")).collect()
    }

    /// Without a key it's the plain hash, as RustCrypto's skein crate makes it
    #[test]
    fn unkeyed_is_the_skein_hash() {
        for message in [&b""[..], b"a", &[7; 64], &[7; 65], &[1; 200]] {
            let expected = ::skein::Skein512::<::skein::consts::U32>::digest(message);
            assert_eq!(mac_512_256(&[], message), expected[..]);
        }
    }

    /// The MACs of the Haskell skein library that clientsession uses, with
    /// the key 0, 1, … 63 (made with `skeinMAC'` in IHP's dev shell)
    #[test]
    fn keyed_is_the_haskell_librarys_mac() {
        let key: Vec<u8> = (0..64).collect();
        let long: Vec<u8> = (0..200).collect();
        for (message, mac) in [
            (
                &b""[..],
                "2f340c177290affb1087de99591064c3d7f1175e6d44483861d99d7ceae4bf40",
            ),
            (
                b"a",
                "3111d432c849ab93e20baaa5c9ae99ae4dc53133e51f62c196e367d3dd96694d",
            ),
            (
                &[7; 64],
                "8e25df41af09fbc5eb4da263c26dc6491155f268d45744316417cf7ffd69571a",
            ),
            (
                &[7; 65],
                "c0c08b7c82fe4b9714d0ccac40d8ca2044c78715896730574d5a023a58bd1640",
            ),
            (
                &long,
                "da3a250c058bf731469d62a0dfc7894c7e2ceb38fd11e0232e9b29a2ab586a03",
            ),
        ] {
            assert_eq!(hex(&mac_512_256(&key, message)), mac, "{}", message.len());
        }
    }
}
