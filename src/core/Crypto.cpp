#include "Crypto.h"

#include <QCryptographicHash>
#include <QMessageAuthenticationCode>
#include <QRandomGenerator>
#include <QString>
#include <QSysInfo>
#include <QtGlobal>

#include <cstring>

namespace {

constexpr char kMagic[4] = {'S', 'I', 'S', '1'};
constexpr int kNonceSize = 12;
constexpr int kTagSize = 32;

inline quint32 rotl32(quint32 x, int n)
{
    return (x << n) | (x >> (32 - n));
}

inline void quarterRound(quint32 &a, quint32 &b, quint32 &c, quint32 &d)
{
    a += b; d ^= a; d = rotl32(d, 16);
    c += d; b ^= c; b = rotl32(b, 12);
    a += b; d ^= a; d = rotl32(d, 8);
    c += d; b ^= c; b = rotl32(b, 7);
}

void chachaBlock(quint32 out[16], const quint32 in[16])
{
    quint32 x[16];
    std::memcpy(x, in, sizeof(x));
    for (int i = 0; i < 10; ++i) {
        quarterRound(x[0], x[4], x[8], x[12]);
        quarterRound(x[1], x[5], x[9], x[13]);
        quarterRound(x[2], x[6], x[10], x[14]);
        quarterRound(x[3], x[7], x[11], x[15]);
        quarterRound(x[0], x[5], x[10], x[15]);
        quarterRound(x[1], x[6], x[11], x[12]);
        quarterRound(x[2], x[7], x[8], x[13]);
        quarterRound(x[3], x[4], x[9], x[14]);
    }
    for (int i = 0; i < 16; ++i)
        out[i] = x[i] + in[i];
}

inline quint32 le32(const uchar *p)
{
    return quint32(p[0]) | (quint32(p[1]) << 8) | (quint32(p[2]) << 16) | (quint32(p[3]) << 24);
}

// XOR the payload with the ChaCha20 keystream. Symmetric: same call decrypts.
QByteArray chacha20Xor(const QByteArray &data, const QByteArray &key, const QByteArray &nonce)
{
    Q_ASSERT(key.size() == 32 && nonce.size() == kNonceSize);

    quint32 state[16];
    state[0] = 0x61707865; state[1] = 0x3320646e;
    state[2] = 0x79622d32; state[3] = 0x6b206574;
    const uchar *k = reinterpret_cast<const uchar *>(key.constData());
    for (int i = 0; i < 8; ++i)
        state[4 + i] = le32(k + i * 4);
    state[12] = 1; // block counter
    const uchar *n = reinterpret_cast<const uchar *>(nonce.constData());
    for (int i = 0; i < 3; ++i)
        state[13 + i] = le32(n + i * 4);

    QByteArray out(data.size(), Qt::Uninitialized);
    const uchar *in = reinterpret_cast<const uchar *>(data.constData());
    uchar *dst = reinterpret_cast<uchar *>(out.data());

    quint32 block[16];
    uchar keystream[64];
    for (qsizetype offset = 0; offset < data.size(); offset += 64) {
        chachaBlock(block, state);
        for (int i = 0; i < 16; ++i) {
            keystream[i * 4 + 0] = uchar(block[i] & 0xff);
            keystream[i * 4 + 1] = uchar((block[i] >> 8) & 0xff);
            keystream[i * 4 + 2] = uchar((block[i] >> 16) & 0xff);
            keystream[i * 4 + 3] = uchar((block[i] >> 24) & 0xff);
        }
        const qsizetype n = qMin<qsizetype>(64, data.size() - offset);
        for (qsizetype i = 0; i < n; ++i)
            dst[offset + i] = in[offset + i] ^ keystream[i];
        ++state[12];
    }
    return out;
}

QByteArray macKey(const QByteArray &key)
{
    return QCryptographicHash::hash(key + "super-infinity-mac", QCryptographicHash::Sha256);
}

} // namespace

namespace crypto {

QByteArray deviceKey()
{
    QByteArray seed = "super-infinity/v1";
    seed += QSysInfo::machineUniqueId();
    if (QSysInfo::machineUniqueId().isEmpty())
        seed += QSysInfo::machineHostName().toUtf8();
    seed += qgetenv("USERNAME");
    seed += qgetenv("USER");
    return QCryptographicHash::hash(seed, QCryptographicHash::Sha256);
}

QByteArray seal(const QByteArray &plain, const QByteArray &key)
{
    QByteArray nonce(kNonceSize, Qt::Uninitialized);
    QRandomGenerator::system()->generate(
        reinterpret_cast<quint32 *>(nonce.data()),
        reinterpret_cast<quint32 *>(nonce.data() + kNonceSize));

    const QByteArray cipher = chacha20Xor(plain, key, nonce);

    QMessageAuthenticationCode mac(QCryptographicHash::Sha256, macKey(key));
    mac.addData(nonce);
    mac.addData(cipher);

    QByteArray blob(kMagic, 4);
    blob += nonce;
    blob += cipher;
    blob += mac.result();
    return blob;
}

QByteArray unseal(const QByteArray &blob, const QByteArray &key, bool *ok)
{
    const auto fail = [ok]() {
        if (ok)
            *ok = false;
        return QByteArray();
    };

    if (blob.size() < 4 + kNonceSize + kTagSize || !blob.startsWith(QByteArray(kMagic, 4)))
        return fail();

    const QByteArray nonce = blob.mid(4, kNonceSize);
    const QByteArray cipher = blob.mid(4 + kNonceSize, blob.size() - 4 - kNonceSize - kTagSize);
    const QByteArray tag = blob.right(kTagSize);

    QMessageAuthenticationCode mac(QCryptographicHash::Sha256, macKey(key));
    mac.addData(nonce);
    mac.addData(cipher);
    if (mac.result() != tag)
        return fail();

    if (ok)
        *ok = true;
    return chacha20Xor(cipher, key, nonce);
}

} // namespace crypto
