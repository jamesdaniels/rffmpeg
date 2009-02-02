require "open-uri"
require "tempfile"
require "stringio"
require "fileutils"

module Rffmpeg
  class RffmpegError < Exception
  end
  
  VERSION = '1.0.0'
    
  class Video
    attr :path
    attr :duration          , true
    attr :bitrate           , true
    attr :fps               , true
    attr :codec             , true
    attr :aspect_ratio      , true
    attr :width             , true
    attr :height            , true
    attr :audio_codec       , true
    attr :audio_sample_rate , true
    attr :audio_format      , true
    attr :audio_bitrate     , true
    attr :author            , true
    attr :title             , true
    
    class <<self
      def open(video_path, logger = nil)     
        return self.new(video_path, logger)
      end
    end
    
    def initialize(video_path, logger = nil) 
      # check if the file exists     
      check = File.open(video_path)
      check.close
      @logger = logger
      # now execute a dummy conversion, so we can see the outputted properties
      @path = video_path
      command = "ffmpeg -i '#{@path}' -vcodec flv -an -t 0.1 '#{@path}-dummy.avi' 2>&1"
      IO.popen(command) do |pipe|
        pipe.each("\r") do |line|
          if line =~ /Duration: (\d{2}):(\d{2}):(\d{2}).(\d{1}), start: 0.000000, bitrate: (\d+) kb/
            @duration = ((($1.to_i * 60 + $2.to_i) * 60 + $3.to_i) * 10 + $4.to_i).to_f / 10
            @bitrate  = $5.to_i
          end
          if line =~ /Stream #(\S+) Video: (\w+), (\w+), (\d+)x(\d+)/
            @codec        = $2
            @aspect_ratio = $4.to_f/$5.to_f
            @width        = $4.to_i/2.to_i*2
            @height       = $5.to_i/2.to_i*2
          end
          if line =~ /Stream #(\S+) Video: (\w+), (\w+), (\d+)x(\d+), (\S+)/
            @fps          = $6.to_f
          end
          if line =~ /Stream #(\S+) Audio: (\w+), (\d+) Hz, (\w+)/
            @audio_codec       = $2
            @audio_sample_rate = $3.to_i
            @audio_format      = $4
          end
          if line =~ /Stream #(\S+) Audio: (\w+), (\d+) Hz, (\w+), (\d+)/
            @audio_bitrate = $5.to_i
          end
        end
      end  
      # if the last command failed, can't use the file: error out
      if $? != 0
        raise RffmpegError, "FFmpeg can't handle #{video_path}: Error Given #{$?}"
      else
        `rm '#{@path}-dummy.avi'` # remove the dummy
      end
    end
    
    def fit_video(width,height)
      if @width * @height > 640*480
        if @aspect_ratio < 1
          [ width, (width*@aspect_ratio/2).to_i*2 ]
        else
          [ (height/@aspect_ratio/2).to_i*2 , height ]
        end
      else
        [ @width, @height ]
      end
    end
    
    def fit_audio(*rates)
      if @audio_sample_rate
        min = rates.min
        rates.collect {|rate| rate * ((rate <= @audio_sample_rate || rate == min) ? 1 : 0)} .max
      else
        rates.max
      end
    end
    
    def save
      return "working on it"
    end
    
    def save_as(video_path)
      return "working on it"
    end
    
    def save_for_ipod(video_path)
      start = Time.now
      run_command(video_path, {
        :acodec => 'aac',
        :ab => '128kb',
        :r => @fps && @fps.to_i || 15,
        :vcodec => 'mpeg4',
        :mbd => 2,
        :flags => '+4mv+trell',
        :aic => 2,
        :cmp => 2,
        :subcmp => 2,
      })
      @logger.info("RFFMEG: created #{video_path} (#{Time.now - start} seconds)") if @logger
    end
    
    def save_for_red5(video_path)
      start = Time.now
      run_command(video_path, {
        :b  => [300,@bitrate].min.to_s + 'kb',
        :r  => @fps && [15,@fps].min.to_i || 15,
        :s  => fit_video(640,480).join('x'),
        :ar => fit_audio(44100, 22050, 11025),
        :g  => 150,
        :cmp    => 2,
        :subcmp => 2,
        :mbd    => 2,
        :flags  => '+aic+cbp+mv0+mv4+trell',
        :vcodec => 'flv',
        :acodec => 'mp3'
      })
      `flvtool2 -U #{video_path}`
      @logger.info("RFFMEG: created #{video_path} (#{Time.now - start} seconds)") if @logger
    end
    
    def save_as_mp3(mp3_path)
      start = Time.now
      run_command(mp3_path, {
        :acodec => 'mp3',
        :ab => '128kb',
        :vn => nil,
        :mbd => 2,
        :cmp => 2,
        :subcmp => 2,
      })
      @logger.info("RFFMEG: created #{video_path} (#{Time.now - start} seconds)") if @logger
    end
    
    def save_thumbnails(thumb_path,number,start_point = 0,end_point = [@duration,1800].min)
      start = Time.now
      run_command(thumb_path, {
        :an => nil,
        :f => 'mjpeg',
        :ss => (end_point-start_point)/(number+1),
        :r  => (number == 1) ? 1 : (number+1)/(end_point-start_point),
        :vframes => number+1
      })
      @logger.info("RFFMEG: created #{thumb_path} (#{Time.now - start} seconds)") if @logger
    end
    
    private
        
    def run_command(save_to, arguments, pipe = nil)
      command = arguments.collect { |option, value| "-#{option} #{"'#{value}'" if value} " } .join(' ')
      command = "ffmpeg -y -i '#{@path}' #{command} '#{save_to}' 2>&1"
      last_line = ""
      IO.popen(command) do |pipe|
        pipe.each("\r") do |line|
          if line =~ /time=(\S+) /
            #puts ($1.to_f/@duration*100).to_i.to_s + "%"
          end
          last_line = line
        end
      end
      if $? != 0
        raise RffmpegError, "FFmpeg command (#{command}) failed: #{last_line.split('ffmpeg:').last}"
      else
        return save_to
      end
    end
  end
  
  class Audio < Video
    
    def initialize(video_path, logger = nil) 
      # check if the file exists     
      check = File.open(video_path)
      check.close
      @logger = logger
      # now execute a dummy conversion, so we can see the outputted properties
      @path = video_path
      command = "ffmpeg -i '#{@path}' -t 0.1 '#{@path}-dummy.mp3' 2>&1"
      IO.popen(command) do |pipe|
        pipe.each("\r") do |line|
          if line =~ /Duration: (\d{2}):(\d{2}):(\d{2}).(\d{1}), start: 0.000000, bitrate: (\d+) kb/
            @duration = ((($1.to_i * 60 + $2.to_i) * 60 + $3.to_i) * 10 + $4.to_i).to_f / 10
            @bitrate  = $5.to_i
          end
          if line =~ /Stream #(\S+) Video: (\w+), (\w+), (\d+)x(\d+), (\S+)/
            @fps          = $6.to_f
            @codec        = $2
            @aspect_ratio = $4.to_f/$5.to_f
            @width        = $4.to_i/2.to_i*2
            @height       = $5.to_i/2.to_i*2
          end
          if line =~ /Stream #(\S+) Audio: (\w+), (\d+) Hz, (\w+)/
            @audio_codec       = $2
            @audio_sample_rate = $3.to_i
            @audio_format      = $4
          end
          if line =~ /Stream #(\S+) Audio: (\w+), (\d+) Hz, (\w+), (\d+)/
            @audio_bitrate = $5.to_i
          end
        end
      end  
      # if the last command failed, can't use the file: error out
      if $? != 0
        raise RffmpegError, "FFmpeg can't handle #{video_path}: Error Given #{$?}"
      else
        `rm '#{@path}-dummy.avi'` # remove the dummy
      end
    end
    
  end

end