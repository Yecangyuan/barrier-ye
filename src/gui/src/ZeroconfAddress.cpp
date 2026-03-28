/*
 * barrier -- mouse and keyboard sharing utility
 * Copyright (C) 2026
 *
 * This package is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * found in the file LICENSE that should have accompanied this file.
 *
 * This package is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

#include "ZeroconfAddress.h"

#include <QtNetwork/QNetworkAddressEntry>
#include <QtNetwork/QNetworkInterface>

namespace {

bool isUsableIPv4Address(const QHostAddress& address)
{
    if (address.protocol() != QAbstractSocket::IPv4Protocol) {
        return false;
    }

    if (address.isNull() || address.isLoopback()) {
        return false;
    }

    const quint32 value = address.toIPv4Address();
    if ((value & 0xffff0000U) == 0xa9fe0000U) {
        return false;
    }

    return true;
}

bool isPrivateIPv4Address(const QHostAddress& address)
{
    const quint32 value = address.toIPv4Address();

    if ((value & 0xff000000U) == 0x0a000000U) {
        return true;
    }

    if ((value & 0xfff00000U) == 0xac100000U) {
        return true;
    }

    if ((value & 0xffff0000U) == 0xc0a80000U) {
        return true;
    }

    return false;
}

} // namespace

QList<QHostAddress> getZeroconfCandidateAddresses()
{
    QList<QHostAddress> addresses;

    for (const QNetworkInterface& networkInterface : QNetworkInterface::allInterfaces()) {
        const auto flags = networkInterface.flags();
        if (!(flags & QNetworkInterface::IsUp) ||
            !(flags & QNetworkInterface::IsRunning) ||
            (flags & QNetworkInterface::IsLoopBack)) {
            continue;
        }

        for (const QNetworkAddressEntry& entry : networkInterface.addressEntries()) {
            if (isUsableIPv4Address(entry.ip())) {
                addresses.append(entry.ip());
            }
        }
    }

    return addresses;
}

QString selectZeroconfServiceAddress(const QList<QHostAddress>& addresses)
{
    QString fallbackAddress;

    for (const QHostAddress& address : addresses) {
        if (!isUsableIPv4Address(address)) {
            continue;
        }

        const QString value = address.toString();
        if (isPrivateIPv4Address(address)) {
            return value;
        }

        if (fallbackAddress.isEmpty()) {
            fallbackAddress = value;
        }
    }

    return fallbackAddress;
}
