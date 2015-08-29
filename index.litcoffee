#Tar parser

Block size is 512 bytes

    BLOCK = 512


    class Tar

     constructor: (encoding = 'utf8') ->
      @data = null
      @files = {}
      @encoding = 'utf8'

     parse: (data) ->
      @data = data
      if @data.byteLength?
       L = @data.byteLength
      else
       L = @data.length

      n = 0
      while n + BLOCK < L
       file = @_parseHeader n
       if file.length > 0 or file.filename isnt ''
        n += BLOCK
        if n + file.length > L
         throw new Error 'Error parsing tar file'
        file.data = @data.slice n, n + file.length
        @files[file.filename] = file
        n += BLOCK * Math.ceil file.length / BLOCK
       else
        break

     _bufferToString: (buffer) ->

If it is an ArrayBuffer

      if buffer.byteLength?
       return String.fromCharCode.apply null, new Uint8Array buffer

If it is NodeJS Buffer

      else
       return buffer.toString 'ascii'

     _parseHeader: (n) ->
      header = {}

      sub = (l) =>
       s = @_bufferToString @data.slice n, n + l
       n += l
       s = s.split "\0", 1
       return s[0]

      len = (l) =>
       s = @_bufferToString @data.slice n, n + l
       n += l
       return parseInt (s.replace /[^\d]/g, ''), 8

      header.filename = sub 100
      header.mode = sub 8
      header.uid = sub 8
      header.gid = sub 8
      header.length = len 12
      header.lastModified = sub 12
      header.checkSum = sub 8
      header.fileType = sub 1
      header.linkName = sub 100

      return header




#Exports

    if module?
     module.exports = Tar

    if window?
     @Tar = Tar
