/*
 * barrier -- mouse and keyboard sharing utility
 * Copyright (C) 2026 Barrier contributors
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

#include "net/SecureSocket.h"
#include "net/SocketMultiplexer.h"
#include "test/global/TestEventQueue.h"
#include "test/global/gtest.h"

TEST(SecureSocketTests, destruct_withoutInitSsl_doesNotCrash)
{
    TestEventQueue events;
    SocketMultiplexer socketMultiplexer;

    SecureSocket socket(&events, &socketMultiplexer, IArchNetwork::kINET,
                        ConnectionSecurityLevel::ENCRYPTED);
}

TEST(SecureSocketTests, close_withoutInitSsl_isIdempotent)
{
    TestEventQueue events;
    SocketMultiplexer socketMultiplexer;

    SecureSocket socket(&events, &socketMultiplexer, IArchNetwork::kINET,
                        ConnectionSecurityLevel::ENCRYPTED);

    socket.close();
    socket.close();
}
