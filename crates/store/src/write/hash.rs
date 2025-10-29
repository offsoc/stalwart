/*
 * SPDX-FileCopyrightText: 2020 Stalwart Labs LLC <hello@stalw.art>
 *
 * SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-SEL
 */

use super::BitmapHash;
use crate::backend::MAX_TOKEN_LENGTH;

impl BitmapHash {
    pub fn new(item: impl AsRef<[u8]>) -> Self {
        Self {
            len: std::cmp::min(item.as_ref().len(), MAX_TOKEN_LENGTH) as u8,
            hash: hash(item),
        }
    }

    pub fn to_u64(&self) -> u64 {
        u64::from_be_bytes(self.hash)
    }
}

fn hash(item: impl AsRef<[u8]>) -> [u8; 8] {
    let item = item.as_ref();
    let mut result = [0u8; 8];

    if item.len() <= 8 {
        result[..item.len()].copy_from_slice(item);
    } else {
        result[..4].copy_from_slice(&xxhash_rust::xxh3::xxh3_64(item).to_le_bytes()[..4]);
        result[4..8].copy_from_slice(&farmhash::hash64(item).to_le_bytes()[..4]);
    }

    result
}

#[derive(Debug, Clone, Copy, Hash, PartialEq, Eq)]
pub struct TokenType {}

impl TokenType {
    pub fn word(field: u8) -> u8 {
        field
    }

    pub fn stemmed(field: u8) -> u8 {
        (1 << 7) | field
    }
}
