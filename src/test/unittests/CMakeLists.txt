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
    ../../test/global/TestEventQueue.h
    ../../test/global/TestUtils.h
    ../../test/global/gmock.h
    ../../test/global/gtest.h
    ../../test/mock/barrier/MockApp.h
    ../../test/mock/barrier/MockArgParser.h
    ../../test/mock/barrier/MockEventQueue.h
    ../../test/mock/barrier/MockKeyMap.h
    ../../test/mock/barrier/MockKeyState.h
    ../../test/mock/barrier/MockScreen.h
    ../../test/mock/io/MockStream.h
    ../../test/mock/ipc/MockIpcServer.h
    ../../test/mock/server/MockConfig.h
    ../../test/mock/server/MockInputFilter.h
    ../../test/mock/server/MockPrimaryClient.h
    ../../test/mock/server/MockServer.h
)

set(sources
    Main.cpp
    barrier/ArgParserTests.cpp
    barrier/ClientArgsParsingTests.cpp
    barrier/ClipboardChunkTests.cpp
    barrier/ClipboardTests.cpp
    barrier/DeprecatedArgsParsingTests.cpp
    barrier/GenericArgsParsingTests.cpp
    barrier/KeyMapTests.cpp
    barrier/KeyStateTests.cpp
    barrier/ServerArgsParsingTests.cpp
    base/EventQueueTests.cpp
    base/PerfMonitorTests.cpp
    base/StringTests.cpp
    ipc/IpcLogOutputterTests.cpp
    net/FingerprintDatabaseTests.cpp
    net/SecureSocketTests.cpp
    net/SecureUtilsTests.cpp
    ../../test/global/TestEventQueue.cpp
    ../../test/global/TestUtils.cpp
)

# platform
if (WIN32)
    file(GLOB platform_sources "platform/MSWindows*.cpp")
    file(GLOB platform_headers "platform/MSWindows*.h")
elseif (APPLE)
    set(platform_sources
        platform/OSXKeyStateTests.cpp
    )
    set(platform_headers)
elseif (UNIX)
    set(platform_sources)
    set(platform_headers)
endif()

list(APPEND sources ${platform_sources})
list(APPEND headers ${platform_headers})

include_directories(
    ../../
    ../../../ext
)

if (UNIX)
    include_directories(
        ../../..
    )
endif()

if (BARRIER_ADD_HEADERS)
    list(APPEND sources ${headers})
endif()

add_executable(unittests ${sources})
target_link_libraries(unittests
    arch base client server common io net platform server synlib mt ipc ${GTEST_LIBRARIES} ${GMOCK_LIBRARIES} ${libs} ${OPENSSL_LIBS})

add_test(NAME unittests COMMAND unittests)
