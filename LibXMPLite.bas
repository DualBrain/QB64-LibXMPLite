'---------------------------------------------------------------------------------------------------------
' LibXMP Lite
' Copyright (c) 2022 Samuel Gomes
'---------------------------------------------------------------------------------------------------------

'---------------------------------------------------------------------------------------------------------
' HEADER FILES
'---------------------------------------------------------------------------------------------------------
'$Include:'./LibXMPLite.bi'
'---------------------------------------------------------------------------------------------------------

$If LIBXMPLITE_BAS = UNDEFINED Then
    $Let LIBXMPLITE_BAS = TRUE
    '-----------------------------------------------------------------------------------------------------
    ' Small test code for debugging the library
    '-----------------------------------------------------------------------------------------------------
    '$Debug
    'If XMPLoadFile("C:\Users\samue\OneDrive\Documents\GitHub\QB64-LibXMPLite\mods\radix-happy_sundays.mod") Then
    '    XMPStartPlayer
    '    Do
    '        XMPUpdatePlayer
    '        Locate 1, 1
    '        Print Using "Order: ###    Pattern: ###    Row: ###    BPM: ###    Speed: ###"; XMPPlayer.frameInfo.position; XMPPlayer.frameInfo.pattern; XMPPlayer.frameInfo.row; XMPPlayer.frameInfo.bpm; XMPPlayer.frameInfo.speed;
    '        Limit 60
    '    Loop While KeyHit <> 27 And XMPPlayer.isPlaying
    '    XMPStopPlayer
    'End If
    'End
    '-----------------------------------------------------------------------------------------------------

    '-----------------------------------------------------------------------------------------------------
    ' FUNCTIONS & SUBROUTINES
    '-----------------------------------------------------------------------------------------------------
    ' Loads the MOD file into memory and prepares all required gobals
    Function XMPFileLoad%% (sFileName As String)
        Shared XMPPlayer As XMPPlayerType

        ' By default we assume a failure
        XMPFileLoad = FALSE

        ' Check if the file exists
        If Not FileExists(sFileName) Then Exit Function

        ' If a song is already loaded then unload and free resources
        If XMPPlayer.context <> NULL Then XMPPlayerStop

        ' Check if the file is a valid module music
        XMPPlayer.errorCode = xmp_test_module(sFileName + Chr$(NULL), XMPPlayer.testInfo)
        If XMPPlayer.errorCode <> 0 Then Exit Function

        ' Initialize the player
        XMPPlayer.context = xmp_create_context

        ' Exit if context creation failed
        If XMPPlayer.context = NULL Then Exit Function

        ' Load the module file
        XMPPlayer.errorCode = xmp_load_module(XMPPlayer.context, sFileName + Chr$(NULL))

        ' Exit if module loading failed
        If XMPPlayer.errorCode <> 0 Then
            ' Free the context
            xmp_free_context XMPPlayer.context
            XMPPlayer.context = NULL
        End If

        ' Initialize the player
        XMPPlayer.errorCode = xmp_start_player(XMPPlayer.context, SndRate, 0)

        ' Exit if starting player failed
        If XMPPlayer.errorCode <> 0 Then
            xmp_release_module XMPPlayer.context
            xmp_free_context XMPPlayer.context
            XMPPlayer.context = NULL
        End If

        ' Allocate the mixer buffer
        XMPPlayer.soundBufferSize = (SndRate \ 40) * XMP_SOUND_BUFFER_FRAME_SIZE
        XMPPlayer.soundBuffer = MemNew(XMPPlayer.soundBufferSize)

        ' Exit if memory was not allocated
        If XMPPlayer.soundBuffer.SIZE = 0 Then
            xmp_end_player XMPPlayer.context
            xmp_release_module XMPPlayer.context
            xmp_free_context XMPPlayer.context
            XMPPlayer.context = NULL
        End If

        ' Set some player properties
        ' These makes the sound quality much better when devices have sample rates other than 44100
        XMPPlayer.errorCode = xmp_set_player(XMPPlayer.context, XMP_PLAYER_INTERP, XMP_INTERP_SPLINE)
        XMPPlayer.errorCode = xmp_set_player(XMPPlayer.context, XMP_PLAYER_DSP, XMP_DSP_ALL)

        ' Allocate a sound pipe
        XMPPlayer.soundHandle = SndOpenRaw

        ' Get the frame information
        xmp_get_frame_info XMPPlayer.context, XMPPlayer.frameInfo

        XMPFileLoad = TRUE
    End Function


    ' Kickstarts playback
    Sub XMPPlayerStart
        Shared XMPPlayer As XMPPlayerType

        If XMPPlayer.context <> NULL Then
            XMPPlayer.isPaused = FALSE
            XMPPlayer.isPlaying = TRUE
        End If
    End Sub


    ' Stops the player and frees all allocated resources
    Sub XMPPlayerStop
        Shared XMPPlayer As XMPPlayerType

        ' Free the player and loaded module
        If XMPPlayer.context <> NULL Then
            ' Free the sound pipe
            SndRawDone XMPPlayer.soundHandle ' Sumbit whatever is remaining in the raw buffer for playback
            SndClose XMPPlayer.soundHandle ' Close QB64 sound pipe

            ' Free the mixer buffer
            MemFree XMPPlayer.soundBuffer

            ' Cleanup XMP
            xmp_end_player XMPPlayer.context
            xmp_release_module XMPPlayer.context
            xmp_free_context XMPPlayer.context
            XMPPlayer.context = NULL
        End If
    End Sub


    ' Restarts playback
    Sub XMPPlayerRestart
        Shared XMPPlayer As XMPPlayerType

        If XMPPlayer.context <> NULL And XMPPlayer.isPlaying And Not XMPPlayer.isPaused Then
            xmp_restart_module XMPPlayer.context
        End If
    End Sub


    ' Jumps to the next position
    Sub XMPPlayerNextPosition
        Shared XMPPlayer As XMPPlayerType

        If XMPPlayer.context <> NULL And XMPPlayer.isPlaying And Not XMPPlayer.isPaused Then
            XMPPlayer.errorCode = xmp_next_position&(XMPPlayer.context)
        End If
    End Sub


    ' Jumps to the previous position
    Sub XMPPlayerPreviousPosition
        Shared XMPPlayer As XMPPlayerType

        If XMPPlayer.context <> NULL And XMPPlayer.isPlaying And Not XMPPlayer.isPaused Then
            XMPPlayer.errorCode = xmp_prev_position&(XMPPlayer.context)
        End If
    End Sub


    ' Just to a specific position
    Sub XMPPlayerSetPosition (nPosition As Long)
        Shared XMPPlayer As XMPPlayerType

        If XMPPlayer.context <> NULL And XMPPlayer.isPlaying And Not XMPPlayer.isPaused Then
            XMPPlayer.errorCode = xmp_set_position&(XMPPlayer.context, nPosition)
        End If
    End Sub


    ' Just to a specific time
    Sub XMPPlayerSeekTime (nTime As Long)
        Shared XMPPlayer As XMPPlayerType

        If XMPPlayer.context <> NULL And XMPPlayer.isPlaying And Not XMPPlayer.isPaused Then
            XMPPlayer.errorCode = xmp_seek_time&(XMPPlayer.context, nTime)
        End If
    End Sub


    ' This handles playback and keeping track of the render buffer
    ' You can call this as frequenctly as you want. The routine will simply exit if nothing is to be done
    Sub XMPPlayerUpdate
        Shared XMPPlayer As XMPPlayerType

        ' If song is done, paused or we already have enough samples to play then exit
        If XMPPlayer.context = NULL Or Not XMPPlayer.isPlaying Or XMPPlayer.isPaused Or SndRawLen(XMPPlayer.soundHandle) > XMP_SOUND_TIME_MIN Then Exit Sub

        ' Clear the render buffer
        MemFill XMPPlayer.soundBuffer, XMPPlayer.soundBuffer.OFFSET, XMPPlayer.soundBufferSize, NULL As BYTE

        ' Render some samples to the buffer
        XMPPlayer.errorCode = xmp_play_buffer(XMPPlayer.context, XMPPlayer.soundBuffer.OFFSET, XMPPlayer.soundBufferSize, 0)

        ' Get the frame information
        xmp_get_frame_info XMPPlayer.context, XMPPlayer.frameInfo

        ' Set playing flag to false if we are not looping and loop count > 0
        If XMPPlayer.isLooping Then
            XMPPlayer.isPlaying = TRUE
        Else
            XMPPlayer.isPlaying = (XMPPlayer.frameInfo.loop_count < 1)
            ' Exit before any samples are queued
            If Not XMPPlayer.isPlaying Then Exit Sub
        End If

        ' Push the samples to the sound pipe
        Dim i As Unsigned Long
        For i = 0 To XMPPlayer.soundBufferSize - XMP_SOUND_BUFFER_SAMPLE_SIZE Step XMP_SOUND_BUFFER_FRAME_SIZE
            SndRaw MemGet(XMPPlayer.soundBuffer, XMPPlayer.soundBuffer.OFFSET + i, Integer) / 32768!, MemGet(XMPPlayer.soundBuffer, XMPPlayer.soundBuffer.OFFSET + i + XMP_SOUND_BUFFER_SAMPLE_SIZE, Integer) / 32768!, XMPPlayer.soundHandle
        Next
    End Sub


    ' Sets the master volume (0 - 100)
    Sub XMPPlayerVolume (nVolume As Long)
        Shared XMPPlayer As XMPPlayerType

        If XMPPlayer.context <> NULL And XMPPlayer.isPlaying Then
            If nVolume < 0 Then
                XMPPlayer.errorCode = xmp_set_player(XMPPlayer.context, XMP_PLAYER_VOLUME, 0)
            ElseIf nVolume > 100 Then
                XMPPlayer.errorCode = xmp_set_player(XMPPlayer.context, XMP_PLAYER_VOLUME, 100)
            Else
                XMPPlayer.errorCode = xmp_set_player(XMPPlayer.context, XMP_PLAYER_VOLUME, nVolume)
            End If
        End If
    End Sub


    ' Gets the master volume
    Function XMPPlayerVolume&
        Shared XMPPlayer As XMPPlayerType

        If XMPPlayer.context <> NULL And XMPPlayer.isPlaying Then
            XMPPlayerVolume = xmp_get_player(XMPPlayer.context, XMP_PLAYER_VOLUME)
        End If
    End Function
    '-----------------------------------------------------------------------------------------------------
$End If
'---------------------------------------------------------------------------------------------------------

