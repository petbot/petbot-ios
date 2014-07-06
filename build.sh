git submodule update --init 
cd kxmovie
git checkout master
git submodule update --init 
cd FFmpeg
git checkout master
cd ..
rake build_ffmpeg
rake build_movie
