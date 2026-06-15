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
    ELevel.h
    Event.h
    EventQueue.h
    EventTypes.h
    FunctionEventJob.h
    IEventJob.h
    IEventQueue.h
    IEventQueueBuffer.h
    IJob.h
    ILogOutputter.h
    Log.h
    NonBlockingStream.h
    PerfMonitor.h
    PriorityQueue.h
    SimpleEventQueueBuffer.h
    Stopwatch.h
    String.h
    TMethodEventJob.h
    Unicode.h
    XBase.h
    finally.h
    log_outputters.h
)

set(sources
    Event.cpp
    EventQueue.cpp
    EventTypes.cpp
    FunctionEventJob.cpp
    Log.cpp
    NonBlockingStream.cpp
    PerfMonitor.cpp
    SimpleEventQueueBuffer.cpp
    Stopwatch.cpp
    String.cpp
    Unicode.cpp
    XBase.cpp
    log_outputters.cpp
)

if (BARRIER_ADD_HEADERS)
    list(APPEND sources ${headers})
endif()

add_library(base STATIC ${sources})

if (UNIX)
    target_link_libraries(base common)
endif()
