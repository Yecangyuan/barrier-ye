/*  barrier -- mouse and keyboard sharing utility
    Copyright (C) 2026

    This package is free software; you can redistribute it and/or
    modify it under the terms of the GNU General Public License
    found in the file LICENSE that should have accompanied this file.

    This package is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

#include "../src/ZeroconfAddress.h"

#include <gtest/gtest.h>

TEST(ZeroconfAddressTests, PrefersPrivateIpv4Addresses)
{
    QList<QHostAddress> addresses{
        QHostAddress("203.0.113.10"),
        QHostAddress("192.168.1.25"),
        QHostAddress("10.1.2.3")
    };

    EXPECT_EQ(selectZeroconfServiceAddress(addresses), "192.168.1.25");
}

TEST(ZeroconfAddressTests, FallsBackToFirstUsableIpv4Address)
{
    QList<QHostAddress> addresses{
        QHostAddress(QHostAddress::LocalHost),
        QHostAddress("169.254.9.8"),
        QHostAddress("203.0.113.10"),
        QHostAddress("198.51.100.20")
    };

    EXPECT_EQ(selectZeroconfServiceAddress(addresses), "203.0.113.10");
}

TEST(ZeroconfAddressTests, OnlyPrefersRfc1918RangeFor172Subnet)
{
    QList<QHostAddress> addresses{
        QHostAddress("172.15.1.10"),
        QHostAddress("172.20.1.15")
    };

    EXPECT_EQ(selectZeroconfServiceAddress(addresses), "172.20.1.15");
}

TEST(ZeroconfAddressTests, ReturnsEmptyWhenNoUsableIpv4AddressExists)
{
    QList<QHostAddress> addresses{
        QHostAddress(QHostAddress::LocalHost),
        QHostAddress("169.254.9.8"),
        QHostAddress("fe80::1")
    };

    EXPECT_TRUE(selectZeroconfServiceAddress(addresses).isEmpty());
}
