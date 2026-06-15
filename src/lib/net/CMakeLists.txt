# barrier -- mouse and keyboard sharing utility
# Copyright (C) 2012-2016 Symless Ltd.
# Copyright (C) 2009 Nick Bolton
#
# This package is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# found in the file LICENSE that should have accompanied this file.
#
# This package is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

set(headers
    ConnectionSecurityLevel.h
    FingerprintData.h
    FingerprintDatabase.h
    IDataSocket.h
    IListenSocket.h
    ISocket.h
    ISocketFactory.h
    ISocketMultiplexerJob.h
    NetworkAddress.h
    SecureListenSocket.h
    SecureSocket.h
    SecureUtils.h
    SocketMultiplexer.h
    TCPListenSocket.h
    TCPSocket.h
    TCPSocketFactory.h
    TSocketMultiplexerMethodJob.h
    XSocket.h
)

set(sources
    FingerprintData.cpp
    FingerprintDatabase.cpp
    IDataSocket.cpp
    NetworkAddress.cpp
    SecureListenSocket.cpp
    SecureSocket.cpp
    SecureUtils.cpp
    SocketMultiplexer.cpp
    TCPListenSocket.cpp
    TCPSocket.cpp
    TCPSocketFactory.cpp
    XSocket.cpp
)

if (BARRIER_ADD_HEADERS)
    list(APPEND sources ${headers})
endif()

add_library(net STATIC ${sources})

if (UNIX)
    target_link_libraries(net mt io ${OPENSSL_LIBS})
endif()
