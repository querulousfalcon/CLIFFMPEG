@echo off

rem --- MAIN ---

echo.
echo Simple FFMPEG Action Script - Version 2019.07.21.1

if "%~dpnx1" == "" goto help

set sources=
set result_file=
set path=%~dp0;%path%
set action_type=join
set workpath=%~dp0

set filter_params=
set audio_params=
set stream_params=
set video_params=
set result_filename=
set source_params=
set vidstab_logfile=
set vidsrctype=video

set param_s_audio_type=
set param_s_video_type=
set param_s_video_type_isvideo=
set param_s_videoheight=
set param_s_crf=
set param_s_bitrate=
set param_s_fps=
set param_s_resize_mode=
set param_s_aspect=
set param_s_effects=_
set param_s_2pass=N
set param_start_at=
set param_duration=
set param_videochannel=0
set param_speedratio=

rem --- Detect Action Type from parameters

set action_type=

set f1_isaudio=x
set f2_isaudio=x
if "%~dpnx2" == "" (
  set action_type=batch
) else (
  if "%~dpnx3" == "" (
    if /i not "%~x1" == ".wav" if /i not "%~x1" == ".mp3" if /i not "%~x1" == ".m4a" if /i not "%~x1" == ".ogg" set f1_isaudio=
    if /i not "%~x2" == ".wav" if /i not "%~x2" == ".mp3" if /i not "%~x2" == ".m4a" if /i not "%~x2" == ".ogg" set f2_isaudio=
  )
)
if "%f1_isaudio%%f2_isaudio%" == "x" set action_type=replace_audio

if not x%action_type% == x goto action_%action_type%

echo.
echo Do you want to join or batch-process?
echo [J]oin
echo [B]atch (default)
set /p actionselection=^>
set action_type=batch
if /i x%actionselection% == xj set action_type=join

goto action_%action_type%


rem --- JOIN VIDEOS INTO NEW RENDERING

:action_join

  set "boxtitle=%~n1"
  title %boxtitle%
  
  set maps=
  set maps_sw=
  set /a counter=0
  
  set "_basefilename=%~nx1"
  set "_basefilename_full=%~dpnx1"
  
  echo.
  echo Files are joined in following order:
  echo - If you want a different order, sort the files diffently in the file explorer,
  echo   select them from last to first and use the first file in the order for the
  echo   drag/drop or context menu operation.
  
  echo.

  :collect_next_file
  
  echo * "%~nx1"
  set sources=%sources% -i %1
  set maps=%maps%[%counter%:0] [%counter%:1] 
  set maps_sw=%maps_sw%[%counter%:1] [%counter%:0] 
  set /a counter+=1
  shift
  
  if not "%~n1" == "" goto collect_next_file

  echo.
  echo - IMPORTANT! For the join to work, all videos need to have the same resolution,
  echo   aspect ratio and audio track index! If not, process the videos first (in a 
  echo   batch run) so they all have matching properties.
  
  call :collect_base_params video audio effects
  
  if /i x%param_s_video_type% == xn (
    call :render_audio_ext "%_basefilename%"
  ) else (
    call :render_video_ext "%_basefilename%"
  )
  
  set "result_file=%_basefilename_full%.joined%result_ext%"

  echo.
  echo Switch Audio/Video channels?
  echo Use only, if you got an audio channel error the first try!
  echo [Y]es
  echo [N]o (default)
  set /p channel_sw=^>
  if /i x%channel_sw% == xy set maps=%maps_sw%
  
  call :render_filtercomplex_params  
  call :render_audio_params
  if /i not x%param_s_video_type% == xn call :render_video_params
  call :execute_ffmpeg "%result_file%"
  
  title [X]%boxtitle%
  
  pause
  
  goto eob


rem --- BATCH-PROCESS VIDEOS INTO NEW RENDERING

:action_batch

  echo.
  if not "%~n2" == "" (
    echo Batch process files:
  ) else (
    echo Process single file:
    echo * "%~nx1"
  )
  
  echo.
  echo What do you want to render? 
  echo [V]ideo file (default)
  echo [A]udio file
  set /p action_batch_mode=^>
  
  if /i x%action_batch_mode% == xa goto action_batch_audio

  set action_batch_mode=v
  
  if not "%~n2" == "" (
    call :collect_base_params video twopass audio effects
  ) else (
    call :collect_base_params video twopass length audio effects
  )
  
  goto render_next_file
  
  :action_batch_audio

  set param_s_video_type_isvideo=0
  
  call :collect_base_params audio length
  set param_s_video_type=c
  call :collect_base_params effects
  
  :render_next_file
  
  set vidsrctype=video
  set "sourceextender=%~x1"
  if not "%sourceextender%%sourceextender%%sourceextender%%sourceextender%%sourceextender%" == "%sourceextender:jpeg=_%%sourceextender:jpg=_%%sourceextender:gif=_%%sourceextender:png=_%%sourceextender:bmp=_%" set vidsrctype=img

  set result_ext=
  
  if /i not "%action_batch_mode%" == "v" (
    call :render_audio_ext "%~nx1"
  ) else ( 
    call :render_video_ext "%~nx1"
  )

  set "result_file=%~dpn1%result_ext%"
  
  if exist "%result_file%" (
    if /i not "%action_batch_mode%" == "v" (
      set "result_file=%~dpn1.audio_extract%result_ext%"
    ) else (
      set "result_file=%~dpn1.new_video%result_ext%"
    )
  )
  
  title %~n1
  
  call :render_stream_params 
  call :render_audio_params 
  if /i x%action_batch_mode% == xv ( 
    call :render_video_params 
  ) else ( 
    set video_params=-vn 
  )
  
  set sources=%start_at% -i %1
  
  call :execute_ffmpeg "%result_file%"
  
  title [X]%~n1

  shift
  
  if not "%~n1" == "" goto render_next_file
  
  echo.
  
  pause
  
  goto eob


rem --- REPLACE AUDIO IN VIDEO

:action_replace_audio
  set param_s_video_type_isvideo=1
  set boxtitle=
  
  rem Detect audio and video file + audio type:
  rem set param_s_audio_type=a
  set audiofileidx=1
  if /i not "%~x1" == ".wav" if /i not "%~x1" == ".mp3" if /i not "%~x1" == ".m4a" if /i not "%~x1" == ".aac" if /i not "%~x1" == ".ogg" set audiofileidx=2
  
  set "sourceextenders=%~x1%~x2"
  
  if not "%sourceextenders%%sourceextenders%%sourceextenders%%sourceextenders%%sourceextenders%" == "%sourceextenders:jpeg=_%%sourceextenders:jpg=_%%sourceextenders:gif=_%%sourceextenders:png=_%%sourceextenders:bmp=_%" set vidsrctype=img
  
  if x%vidsrctype% == ximg goto action_replace_audio__imagevid
  
  if %audiofileidx% == 1 (
    set sources=-i "%~dpnx2" -i "%~dpnx1" 
    set "result_file=%~dpn2.new_audio%~x2"
    set "boxtitle=%~n2"
  ) else (
    set sources=-i "%~dpnx1" -i "%~dpnx2" 
    set "result_file=%~dpn1.new_audio%~x1"
    set "boxtitle=%~n1"
  )
  
  title %boxtitle%
  
  echo.
  echo Replace audio:
  
  set param_s_video_type=c
  
  call :collect_base_params audio videochannel effects

  set filter_params=-map 1:0 -map 0:%param_videochannel%
  
  goto action_replace_audio__render
  
  :action_replace_audio__imagevid
  
  echo.
  echo Render video from image:
  
  call :collect_base_params video audio length effects
  
  call :render_video_ext

  if %audiofileidx% == 1 (
    set sources=-i "%~dpnx2" -i "%~dpnx1" 
    set "result_file=%~dpn2%result_ext%"
    set "boxtitle=%~n2"
  ) else (
    set sources=-i "%~dpnx1" -i "%~dpnx2" 
    set "result_file=%~dpn1%result_ext%"
    set "boxtitle=%~n1"
  )
  
  title %boxtitle%
  
  :action_replace_audio__render

  call :render_stream_params 
  call :render_audio_params 
  call :render_video_params 

  call :execute_ffmpeg "%result_file%"
  
  title [X]%boxtitle%
  
  pause

  goto eob
  

rem --- SUBROUTINES


:render_video_ext

  set result_ext=.mp4
  if /i x%param_s_video_type% == xc set result_ext=%~x1
  if /i x%param_s_video_type% == xm set result_ext=.mpg
  if /i x%param_s_video_type% == xx set result_ext=.avi
  if /i x%param_s_video_type% == xj set result_ext=.jpg
  if /i x%param_s_video_type% == xp set result_ext=.png
  if /i x%param_s_video_type% == xw set result_ext=.webm
  if /i x%param_s_video_type% == xg set result_ext=.gif
  if /i x%param_s_video_type% == xi set result_ext=.gif

  goto eob
              
              
:render_audio_ext

  set result_ext=.avi
  if /i x%param_s_audio_type% == xc set result_ext=%~x1
  if /i x%param_s_audio_type% == xw set result_ext=.wav
  if /i x%param_s_audio_type% == xm set result_ext=.mp3
  if /i x%param_s_audio_type% == xa set result_ext=.m4a
  if /i x%param_s_audio_type% == xo set result_ext=.ogg
  if /i x%param_s_audio_type% == xf set result_ext=.flac
  if /i x%param_s_audio_type% == x3 set result_ext=.ac3
  
  goto eob


:collect_base_params

  if "%1" == "" goto eob
  
  goto collect_base_params__%1
  
  :collect_base_params__video
  
  echo.
  echo Select processing of the video data:
  if not x%action_type%==xjoin echo [C]opy source video
  echo [H]264 encoding (default)
  echo [X]Vid encoding
  echo [M]PEG2 encoding
  echo [W]EBM encoding
  if not %action_type% == replace_audio (
    echo [J]PEG images sequence
    echo [P]NG images sequence
    if not %action_type% == join (
      echo [G]IF animation ^(HD^)
      echo G[I]F animation ^(LQ^) 
    )
  )
  if x%action_type%==xjoin (
    echo [N]o video ^(audio only^)
  )
  set /p param_s_video_type=^>
  set param_s_video_type_isvideo=1
  if /i x%param_s_video_type% == x set param_s_video_type=h
  if /i x%param_s_video_type% == xc goto collect_base_params__next
  if /i x%param_s_video_type% == xn goto collect_base_params__next
  if /i x%param_s_video_type% == xj set param_s_video_type_isvideo=0
  if /i x%param_s_video_type% == xp set param_s_video_type_isvideo=0
  if /i x%param_s_video_type% == xg set param_s_video_type_isvideo=0
  if /i x%param_s_video_type% == xi set param_s_video_type_isvideo=0

  if %param_s_video_type_isvideo% == 0 goto collect_base_params__bitrate_end

  echo.
  echo Set video encoding quality by:
  echo [Q]uality (default)
  echo [A]bsolute bitrate
  echo [C]omputed bitrate
  set choice_bitrate=
  set /p choice_bitrate=^>
  if x%choice_bitrate% == x set choice_bitrate=q
  
  if /i x%choice_bitrate% == xa goto collect_base_params__bitrate_a
  if /i x%choice_bitrate% == xc goto collect_base_params__bitrate_c

  echo.
  echo Set video encoding quality 
  echo Values: 0 - 50
  echo 0 is lossless, 50 is very bad quality
  echo empty: 21
  set param_s_bitrate=
  set param_s_crf=
  set /p param_s_crf=^>
  if x%param_s_crf% == x set param_s_crf=21
  goto collect_base_params__bitrate_end
  
  :collect_base_params__bitrate_a
  
  echo.
  echo Enter video encoding bitrate in kilobit
  echo Examples for kilobit values: "150", "3500", "6000"
  echo Empty input causes the using of 1500 kilobit.
  set param_s_bitrate=
  set /p param_s_bitrate=^>
  if x%param_s_bitrate% == x set param_s_bitrate=1500
  goto collect_base_params__bitrate_end

  :collect_base_params__bitrate_c
  
  echo.
  echo Enter size for videodata in kilobytes
  echo Examples: "200.000" (200 MBytes), "500", "1.500.000" (1.5GBytes)
  set _param_destsize=
  set /p _param_destsize=^>
  set _param_destsize=%_param_destsize:.=%

  echo.
  echo Enter length of video in Minutes:Seconds
  echo Examples: "60", "1:30", "120:25"
  set _param_destlength=
  set /p _param_destlength=^>
  set _param_destlength_orig=%_param_destlength%
  set _param_destlength=%_param_destlength::=*60+%
  rem Minutes only? Convert to seconds:
  if  "%_param_destlength%" == "%_param_destlength_orig%" set _param_destlength=%_param_destlength%*60

  rem kb-size / length in seconds = kbytes per second * 8 = kbit per second
  set /a param_s_bitrate = %_param_destsize% / (%_param_destlength%) * 8
  
  echo.
  echo Computed bitrate: %param_s_bitrate%
  
  :collect_base_params__bitrate_end
  
  if x%action_type% == xjoin goto collect_base_params__afterlineheight
  
  echo.
  echo Set line height of video
  echo Examples: "360", "480", "720", "1080"
  echo Empty input causes the using of the original videos height.
  set /p param_s_videoheight=^>

  :collect_base_params__afterlineheight

  echo.
  echo Set the aspect ratio of the video.
  echo Examples: "4:3", "5:4", "14:9", "16:9", "21:9"
  if x%param_s_videoheight% == x echo Empty input causes the using of the original videos aspect ratio.
  if not x%param_s_videoheight% == x echo Empty input causes the using of ratio 16:9
  set /p param_s_aspect=^>
  if not x%param_s_videoheight% == x if x%param_s_aspect% == x set param_s_aspect=16:9
  
  if "%param_s_aspect%" == "" goto collect_base_params__after_ratio

  echo.
  echo How should the original video be fit into the new videos size?
  echo [C]rop the original video image (cut from left+right or top+bottom)
  echo [P]ad the original video with black bars (default)
  echo [R]esize/stretch the image to the new ratio
  set /p param_s_resize_mode=^>
  if x%param_s_resize_mode% == x set param_s_resize_mode=p

  :collect_base_params__after_ratio
  
  echo.
  echo Set the frames per second (FPS)
  echo Examples: "25", "29.970029", "30", "60", "ntsc", "pal", "film"
  echo Empty input causes the using of the original videos FPS.
  set /p param_s_fps=^>
  
  goto collect_base_params__next
  
  :collect_base_params__effects  
  
  if x%param_s_video_type%%param_s_audio_type% == xcc goto collect_base_params__next
  
  echo.
  echo Additional effects (combine tags as needed):
  if not x%action_type%==xjoin (
    if not x%param_s_video_type% == xc if not x%param_s_video_type% == xn (
      echo [1] Weak sharpening
      echo [2] Medium sharpening
      echo [3] Strong sharpening
      echo [G] Add film grain ^(recomm. only for high bitr. with low quality source^)
      echo [I] De-Interlace
      if %param_s_video_type_isvideo% == 1 (
        echo [F] Fade in ^(3 secs from black^)
        echo [S] Stabilize
        echo [P] Interpolate ^(HD^)
        echo [O] Interpolate ^(LQ^)
      )
    )
    echo [E] Change speed
    if not x%param_s_audio_type% == xc (
      if %param_s_video_type_isvideo% == 1 (
        if x%param_s_video_type% == xc echo [F] Fade in
        echo [N] Normalized audio
        echo [C] Compressed audio
        echo [T] Trim digital silence
        echo [A] Trim analog silence
        echo [M] Mono audio
      )
    )
  ) else (
    echo [M] Mono audio
  )
  echo Examples: "2", "1G", "F"
  set /p param_s_effects=^>
  if x%param_s_effects% == x set param_s_effects=_
  
  if /i "%param_s_effects:e=_%" == "%param_s_effects%" goto collect_base_params__effects_end
  
  echo.
  echo Set speed change ratio [slower 0.5 - 2 faster]
  echo Empty input causes no speed change
  set /p param_speedratio=^>
  
  :collect_base_params__effects_end

  goto collect_base_params__next
  
  :collect_base_params__length
  
  echo.
  echo Skip time from the beginning of the original video.
  echo Format: "hh:mm:ss[.xxx]" or "ss[.xxx]"
  echo Empty input causes a start from the beginning of the original video.
  set /p param_start_at=^>
  
  echo.
  echo Set duration of the new video 
  echo Format: "hh:mm:ss[.xxx]" or "ss[.xxx]"
  echo Empty input causes the processes the original video until its end.
  set /p param_duration=^>
  
  goto collect_base_params__next
  
  :collect_base_params__audio
  
  set default_audio_type=m
  if /i x%param_s_video_type% == xh set default_audio_type=a
  if /i x%param_s_video_type% == xm set default_audio_type=2
  if /i x%param_s_video_type% == xc set default_audio_type=c
  if /i x%param_s_video_type% == xw set default_audio_type=o
  
  if /i x%param_s_video_type% == xj set param_s_audio_type=n
  if /i x%param_s_video_type% == xp set param_s_audio_type=n
  if /i x%param_s_video_type% == xg set param_s_audio_type=n
  if /i x%param_s_video_type% == xi set param_s_audio_type=n
  
  if x%param_s_audio_type% == xn goto collect_base_params__next
  
  echo.
  echo Set audio encoder:
  if /i not x%param_s_video_type% == xn if x%default_audio_type% == xn ( echo [N]o audio ^(default^)  ) else ( echo [N]o audio )
  if not x%action_type%==xjoin if x%default_audio_type% == xc ( echo [C]opy from source file ^(default^)  ) else ( echo [C]opy from source file )
  echo [W]AV
  echo [F]LAC
  if x%default_audio_type% == xm ( echo [M]P3 - libmp3lame ^(default^)       ) else ( echo [M]P3 - libmp3lame )
  if x%default_audio_type% == xo ( echo [O]GG - libvorbis ^(default^)        ) else ( echo [O]GG - libvorbis )
  if x%default_audio_type% == xa ( echo [A]AC - aac ^(default^) ) else ( echo [A]AC - aac )
  if x%default_audio_type% == x2 ( echo MP[2] - mp2 ^(default^)              ) else ( echo MP[2] - mp2 )
  echo AC[3]
  set /p param_s_audio_type=^>
  if x%param_s_audio_type% == x set param_s_audio_type=%default_audio_type%
  set param_audiobitrate=
  if /i x%param_s_audio_type% == xw goto collect_base_params__next
  if /i x%param_s_audio_type% == xf goto collect_base_params__next
  if /i x%param_s_audio_type% == xc goto collect_base_params__next
  
  set default_audio_bitrate=192
  if /i x%param_s_audio_type% == xa set default_audio_bitrate=160
  if /i x%param_s_audio_type% == x2 set default_audio_bitrate=256
  if /i x%param_s_audio_type% == xo set default_audio_bitrate=128
  
  if /i x%param_s_audio_type% == xn (
    set default_audio_bitrate=0
    goto collect_base_params__next
  )
  
  echo.
  echo Enter audio bitrate in kilobit
  echo Examples: "128", "192", "320", "5"
  echo Empty input causes the using of %default_audio_bitrate% kilobit.
  echo Values 0-10 cause the variable bitrate in the quality setting of the encoder.
  if /i x%param_s_audio_type% == xa echo AAC: worst 1 - 5 best
  if /i x%param_s_audio_type% == xm echo MP3: best 0 - 9 worst
  if /i x%param_s_audio_type% == xo echo OGG: worst 0 - 10 best
  set /p param_audiobitrate=^>
  if x%param_audiobitrate% == x set param_audiobitrate=%default_audio_bitrate%

  goto collect_base_params__next

  :collect_base_params__videochannel

  echo.
  echo Channel for videostream in video file
  echo Examples: "0", "1", "2", ...
  echo Empty input causes the using of channel 0 (usually the right one).
  set /p param_videochannel=^>
  if x%param_videochannel% == x set param_videochannel=0
  
  goto collect_base_params__next
  
  :collect_base_params__twopass
  
  if not "%param_s_crf%" == "" goto collect_base_params__next
  if /i x%param_s_video_type% == xc goto collect_base_params__next
  if %param_s_video_type_isvideo% == 0 goto collect_base_params__next
  
  echo.
  echo Two-Pass encoding?
  echo [Y]es
  echo [N]o (default)
  set /p param_s_2pass=^>
  if x%param_s_2pass% == x set param_s_2pass=N
  
  goto collect_base_params__next

  :collect_base_params__next
  
  shift
  goto collect_base_params

  goto eob


:render_filtercomplex_params
  if /i x%param_s_video_type%==xn (
    rem audio only
    set filter_params=-filter_complex "concat=n=%counter%:v=0:a=1"
  ) else (
    set filter_params=-filter_complex "%maps% concat=n=%counter%:v=1:a=1 [v] [a]" -map "[v]" -map "[a]"
  )
  goto eob

         
:render_audio_params 
  set afilter_fade=
  set afilter_downmix=
  set afilter_trim=
  set afilter_speed=
  set afilter_silentintro=
  set audiobitrate=
  set audiochannels=2
  set audio_params= 

  if "%param_s_audio_type%" == "" set param_s_audio_type=m

  if /i "%param_s_audio_type%" == "c" (
    set audio_params=-c:a copy
    goto eob
  )

  if /i "%param_s_audio_type%" == "n" (
    set audio_params=-an
    goto eob
  )

  if x%action_type% == xjoin goto render_audio_params__aftereffects

  set "afilter_downmix=,aresample=matrix_encoding=dplii"
  
  if not "%param_s_effects%" == "%param_s_effects:f=_%" set "afilter_fade=,afade=in:curve=esin:d=1.5"
  if not "%param_s_effects%" == "%param_s_effects:n=_%" set "afilter_loud=,compand=attacks=.0001|.0001:decays=2|2:points=-90/-90|-60/-5|0/0:soft-knee=0.01:gain=-.1:volume=-30:delay=0"
  if not "%param_s_effects%" == "%param_s_effects:c=_%" set "afilter_loud=,compand=attacks=.0001|.0001:decays=.25|.25:points=-90/-90|-60/-7|0/0:soft-knee=0.01:gain=-.4:volume=-30:delay=0"
  if not "%param_s_effects%" == "%param_s_effects:t=_%" (
    set "afilter_trim=,silenceremove=start_periods=1:stop_periods=1"
    set "afilter_silentintro=,adelay=400|400"
  )
  if not "%param_s_effects%" == "%param_s_effects:a=_%" (
    set "afilter_trim=,silenceremove=start_periods=1:stop_periods=1:start_threshold=-30dB"
    set "afilter_silentintro=,adelay=400|400"
  )
  if not x%param_speedratio% == x set afilter_speed=,atempo=%param_speedratio%
  if not "%param_s_effects%" == "%param_s_effects:m=_%" set "afilter_downmix=,aresample=rematrix_maxval=1.0"

  :render_audio_params__aftereffects

  if not "%param_s_effects%" == "%param_s_effects:m=_%" set audiochannels=1

  set audiochannels=-ac %audiochannels%

  if x%param_audiobitrate% == x goto render_audio_params__afterbitrate

  set audiobitrate=%param_audiobitrate%
  
  if /i %audiobitrate% LEQ 10 (
    set audiobitrate=-aq %audiobitrate%
  ) else (
    set audiobitrate=-ab %audiobitrate%k
  )
  :render_audio_params__afterbitrate

  if /i "%param_s_audio_type%" == "a" set audio_params=-strict -2 -acodec aac -profile:a aac_main %audiochannels% %audiobitrate% -bsf:a aac_adtstoasc
  if /i "%param_s_audio_type%" == "m" set audio_params=-acodec libmp3lame -joint_stereo 1 -compression_level 0 %audiochannels% %audiobitrate%
  if /i "%param_s_audio_type%" == "2" set audio_params=-acodec mp2 %audiochannels% %audiobitrate%
  if /i "%param_s_audio_type%" == "o" set audio_params=-acodec libvorbis -compression_level 10 %audiochannels% %audiobitrate%
  if /i "%param_s_audio_type%" == "3" set audio_params=-acodec ac3 %audiochannels% %audiobitrate%
  if /i "%param_s_audio_type%" == "w" set audio_params=-acodec pcm_s16le %audiochannels%
  if /i "%param_s_audio_type%" == "f" set audio_params=-acodec flac %audiochannels%
  
  if not x%action_type% == xjoin set audio_params=%audio_params% -af "anull %afilter_downmix% %afilter_trim% %afilter_speed% %afilter_loud% %afilter_fade% %afilter_silentintro%"
  rem else error: "-vf/-af/-filter and -filter_complex cannot be used together for the same stream"

  goto eob


:render_stream_params
  set duration=
  set start_at=      

  if not "%param_duration%" == "" set duration=-to %param_duration%
  if not "%param_start_at%" == "" set start_at=-accurate_seek -ss %param_start_at%
  
  set stream_params=%duration%

  goto eob


:render_video_params
  if /i "%param_s_video_type%" == "c" (
    set video_params=-c:v copy
    goto eob
  )         
  
  set crf=
  set aspect=
  set vfiltergraph=
  set vfiltergraph2=
  set fps=        
  set bitrate=
  set encoder=
  set shortestflag=
  set vfilter_deshake=
  set vfilter_unsharp=
  set vfilter_scale=
  set vfilter_resizemode=
  set vfilter_noise=
  set vfilter_fade=
  set vfilter_deinterl=
  set vfilter_interp=
  set vfilter_speed=
  set vfilter_format=
  set video_params=
  set video_params2=
  
  set vidstab_logfile=vidstab_%random%%random%%random%.trf

  if not x%param_s_crf% == x set crf=-crf %param_s_crf%
  if not x%param_s_bitrate% == x set bitrate=-b:v %param_s_bitrate%k
  if not x%param_s_fps% == x set fps=-r %param_s_fps%
  
  set encoder=-vcodec libx264
  if /i x%param_s_video_type% == xm set encoder=-vcodec mpeg2video
  if /i x%param_s_video_type% == xx set encoder=-vcodec libxvid
  if /i x%param_s_video_type% == xj set encoder=-f image2
  if /i x%param_s_video_type% == xp set encoder=-f image2
  if /i x%param_s_video_type% == xw set encoder=-vcodec libvpx

  if x%action_type% == xjoin goto render_video_params__aftereffects

  if x%vidsrctype% == ximg set vfilter_format=,format=rgb24
  
  if /i not x%param_s_video_type% == xc if not "%param_s_aspect%" == "" (
    if /i x%param_s_resize_mode% == xc set vfilter_resizemode=,crop=min^(iw\,2*ceil^(^(ih*^(%param_s_aspect::=/%^)^)*0.5^)^):ow/^(%param_s_aspect::=/%^)
    if /i x%param_s_resize_mode% == xp set vfilter_resizemode=,pad=max^(iw\,2*ceil^(^(ih*^(%param_s_aspect::=/%^)^)*0.5^)^):ow/^(%param_s_aspect::=/%^):^(ow-iw^)/2:^(oh-ih^)/2:#000000
  )
  
  rem todo: pad with blurred background
  rem ffmpeg -i input.mp4 -lavfi "[0:v]scale=iw:2*trunc(iw*16/18),boxblur=luma_radius=min(h\,w)/20:luma_power=1:chroma_radius=min(cw\,ch)/20:chroma_power=1[bg];[bg][0:v]overlay=(W-w)/2:(H-h)/2,setsar=1" {-other parameters} output.mp4

  if not x%param_s_videoheight% == x set vfilter_scale=,scale=2*ceil((%param_s_videoheight%*^(%param_s_aspect::=/%))*0.5):%param_s_videoheight%:flags=lanczos
  
  if not "%param_s_effects%" == "%param_s_effects:s=_%" set vfilter_deshake=,vidstabtransform=smoothing=20:optzoom=0:zoom=5:optalgo=avg:relative=1:input=%vidstab_logfile%
  if not "%param_s_effects%" == "%param_s_effects:f=_%" set vfilter_fade=,fade=in:st=0.5:d=2.5
  if not "%param_s_effects%" == "%param_s_effects:1=_%" set vfilter_unsharp=,unsharp=5:5:1.0:5:5:1.0
  if not "%param_s_effects%" == "%param_s_effects:2=_%" set vfilter_unsharp=,unsharp=5:5:2.0:5:5:2.0
  if not "%param_s_effects%" == "%param_s_effects:3=_%" set vfilter_unsharp=,unsharp=5:5:3.0:5:5:3.0
  if not "%param_s_effects%" == "%param_s_effects:g=_%" set vfilter_noise=,noise=c0s=17:c0f=a+t
  if not "%param_s_effects%" == "%param_s_effects:i=_%" set vfilter_deinterl=,kerndeint
  if not "%param_s_effects%" == "%param_s_effects:p=_%" set vfilter_interp=,minterpolate=mi_mode=mci:me_mode=bidir:vsbmc=1
  if not "%param_s_effects%" == "%param_s_effects:o=_%" set vfilter_interp=,minterpolate=mi_mode=blend
  
  if x%param_speedratio% == x goto render_video_params__afterspeed
  
  rem 0.5 - 1.0  >  2.0 - 1.0
  if /i %param_speedratio% LEQ 1 set vfilter_speed=,setpts=3-(%param_speedratio%*2)*PTS
  rem 1.0 - 2.0  >  1.0 - 0.5
  if /i %param_speedratio% GTR 1 set vfilter_speed=,setpts=(1-((%param_speedratio%-1)*.5))*PTS
  
  :render_video_params__afterspeed

  :render_video_params__aftereffects

  if /i not x%param_s_video_type% == xc if not "%param_s_aspect%" == "" set aspect=-aspect %param_s_aspect%
  
  if /i x%param_s_video_type% == xj (
    set param_s_2pass=n
    set bitrate=-qscale:v 2
    set crf=
  )
  
  if /i x%param_s_video_type% == xp (
    set param_s_2pass=n
    set bitrate=-qscale:v 2
    set crf=
  )
  
  if %action_type% == replace_audio (
    if x%vidsrctype% == ximg (
      if /i not x%param_s_video_type% == xg (
        if /i not x%param_s_video_type% == xi (
          set source_params=-loop 1
          set shortestflag=-shortest
        )
      )
    )
  )
  
  if /i x%param_s_video_type% == xg goto render_video_params_animgif
  if /i x%param_s_video_type% == xi goto render_video_params_animgif
  
  if not x%action_type% == xjoin set vfiltergraph=-vf "null %vfilter_deinterl% %vfilter_speed% %vfilter_interp% %vfilter_format% %vfilter_resizemode% %vfilter_scale% %vfilter_deshake% %vfilter_fade% %vfilter_unsharp% %vfilter_noise%"
  rem else error: "-vf/-af/-filter and -filter_complex cannot be used together for the same stream"

  set video_params=%vfiltergraph% %encoder% %crf% %fps% %aspect% %bitrate% %shortestflag%
  
  goto eob
  
  :render_video_params_animgif

  set param_s_2pass=n
  set bitrate=
  set crf=
  
  set vfiltergraph=-vf "null %vfilter_deinterl% %vfilter_speed% %vfilter_format% %vfilter_resizemode% %vfilter_scale% %vfilter_deshake% %vfilter_fade% %vfilter_unsharp% %vfilter_noise% ,palettegen=stats_mode=full"
  set video_params=%vfiltergraph% %fps% %aspect%
  rem for GIF:
  set gif_dither=bayer:bayer_scale=3
  if /i x%param_s_video_type% == xi set gif_dither=none
  set vfiltergraph2=-lavfi "null %vfilter_deinterl% %vfilter_speed% %vfilter_interp% %vfilter_format% %vfilter_resizemode% %vfilter_scale% %vfilter_deshake% %vfilter_fade% %vfilter_unsharp% %vfilter_noise% [x]; [x][1:v] paletteuse=dither=%gif_dither%"
  set video_params2=%vfiltergraph2% %fps% %aspect%

  goto eob
  
  
:execute_ffmpeg

  set "result_filename_pre=%~dpn1"
  set "result_filename_post=%~x1"
  set "result_filename=%result_filename_pre%%result_filename_post%"
  set "result_2passlog_pre=%result_filename_pre%_%random%"
  
  if not x%vidsrctype% == ximg (
    if /i x%param_s_video_type% == xj set "result_filename=%result_filename_pre%.%%12d%result_filename_post%"
    if /i x%param_s_video_type% == xp set "result_filename=%result_filename_pre%.%%12d%result_filename_post%"
  )

  if not exist "%result_filename%" goto execute_ffmpeg__afterfilenamefind
  
  set /a result_filenamecounter=0
  :execute_ffmpeg__findfilename
  set /a result_filenamecounter+=1
  set "result_filename=%result_filename_pre%.%result_filenamecounter%%result_filename_post%"
  if exist "%result_filename%" goto execute_ffmpeg__findfilename
  :execute_ffmpeg__afterfilenamefind
  
  if "%param_s_effects%" == "%param_s_effects:s=_%" goto execute_ffmpeg__start_encoding
  
  echo.
  
  @echo on 
  ffmpeg.exe %source_params% -y %sources% -an %stream_params% -vf "vidstabdetect=shakiness=10:stepsize=12:result=%vidstab_logfile%" -vcodec rawvideo -f null -
  @echo off
  
  :execute_ffmpeg__start_encoding

  if /i x%param_s_video_type% == xg goto execute_ffmpeg__animgif
  if /i x%param_s_video_type% == xi goto execute_ffmpeg__animgif
  
  if /i x%param_s_2pass% == xy goto execute_ffmpeg__twopass

  @echo on
  ffmpeg.exe %source_params% -y %sources% %filter_params% %audio_params% %stream_params% %video_params% "%result_filename%"
  @echo off

  goto execute_ffmpeg__finalize

  :execute_ffmpeg__twopass
  
  @echo on
  ffmpeg.exe %source_params% -y %sources% %filter_params% %audio_params% %stream_params% %video_params% -pass 1 -passlogfile "%result_2passlog_pre%" "%result_filename%"
  @echo off
  ffmpeg.exe %source_params% -y %sources% %filter_params% %audio_params% %stream_params% %video_params% -pass 2 -passlogfile "%result_2passlog_pre%" "%result_filename%"

  del /f /q "%result_2passlog_pre%*log*"

  goto execute_ffmpeg__finalize
  
  :execute_ffmpeg__animgif

  del /f /q "%result_filename%.png"
  
  @echo on
  ffmpeg.exe %source_params% -y %sources% %filter_params% %stream_params% %video_params% "%result_filename%.png"
  ffmpeg.exe %source_params% -y %sources% -i "%result_filename%.png" %filter_params% %stream_params% %video_params2% "%result_filename%"
  @echo off
  
  del /f /q "%result_filename%.png"
  
  goto execute_ffmpeg__finalize
  
  :execute_ffmpeg__finalize

  if not "%vidstab_logfile%" == "" del /f /q "%~dp0%vidstab_logfile%"
  
  goto eob
  

:createsendto
  set cstcreatescript=ffmpeg_processor_createsendto.js
  set "csttargetpath=%~dpnx0"
  set "cstworkpath=%~dp0"
  
  echo var renderedlink = WScript.CreateObject( "WScript.Shell" ).CreateShortcut( %cstshortcutfilename:\=\\% ); > %cstcreatescript%
  echo renderedlink.TargetPath = %csttargetpath:\=\\%; >> %cstcreatescript%
  echo renderedlink.WorkingDirectory = %cstworkpath:\=\\%; >> %cstcreatescript%
  echo renderedlink.IconLocation = "%SystemRoot:\=\\%\\system32\\SHELL32.dll, 68"; >> %cstcreatescript%
  echo renderedlink.Save(); >> %cstcreatescript%
  
  cscript /nologo %cstcreatescript%
  
  del /f /q %cstcreatescript%    
  
  if exist "%cstshortcutfilename%" (
    echo Link created. Script can now be executed from file explorer through the context
    echo menu option "Send To" for single or multiple selected files: 
    echo Select "FFMPEG-Processor".
  ) else (
    echo Link couldnt be created. Expected filename: 
    echo %cstshortcutfilename%
  )

  goto eob
  
  
:help
  echo.
  echo Drag'n'drop files onto the batch file to:
  echo - Join videos into a single video.
  echo - ^(Batch^) process video^(s^) into new video^(s^).
  echo - Extract audio file^(s^) from video file^(s^).
  echo - Replace audio track in a video file.
  echo.
  echo Replacing audio is done by dropping one video and one music file onto the
  echo batch file.
  echo.
  echo Needs ffmpeg.exe in the folder of the batch file or the ffmpeg.exe folder
  echo in PATH.
  echo.
  echo http://www.ffmpeg.org/
  echo.
  echo Developed under Windows 7, 64Bit.
  echo. 

  set "cstshortcutfilename=%appdata%\Microsoft\Windows\SendTo\FFMPEG-Processor.lnk"
  
  if exist "%cstshortcutfilename%" (
    echo Script available through the Send-To option. Filename of the link:
    echo %cstshortcutfilename%
    echo.
    pause 
    goto eob
  )

  echo Do you want to have access to this script through the Send-To option of the
  echo Windows file explorer now?
  echo [Y]es or ENTER creates automatically a link to this script.
  set /p ask_createlink=^>
  if /i x%ask_createlink% == x set ask_createlink=y
  if /i x%ask_createlink% == xy (
    echo.
    call :createsendto
    echo.
    pause
  )
  
  goto eob
  

:eob


