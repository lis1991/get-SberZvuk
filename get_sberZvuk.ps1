param(
    [string[]] $Links, 
    [String] $Token,
    [String] $Login,
    [String] $Password
)

$conf = gc .\config.json|ConvertFrom-Json
$loginBody = @{}

if ($Token) {'Using Token to log in'}
elseif ($Login -and $Password) {
    $loginBody.email = $Login
    $loginBody.password = $Password
}
Else {
    if ($conf.token -ne '') {
        $token = $conf.token
        'Using Token to log in'
    }
    elseif ($conf.email -ne '' -and $conf.password -ne '') {
        $loginBody.email = $conf.email
        $loginBody.password = $conf.password
    }
    elseif (!($token) -and $conf.token -eq '' -and ($conf.email -eq '' -or $conf.password -eq '')) {
        $loginBody.email = read-host 'Insert login (email)'
        $loginBody.password = read-host 'Insert password'
    }
}

if (!($token)) {
    try {
        $token = (Invoke-RestMethod -Method Post -ContentType 'application/x-www-form-urlencoded' -Uri 'https://zvuk.com/api/tiny/login/email' -Body $loginBody).result.token
    }
    catch {
        $_.Exception
        if ($_.Exception -match '\(403\)\sForbidden') {
            write-host 'Dont forget to put CORRECT login and password to config.json' -foreground RED
            break
        }
    }
    #$token = $login.result.token
    #$token
}

#$login
'got token: ' + $token
$header = @{'x-auth-token' = $token}
#$prof = Invoke-RestMethod -uri 'https://zvuk.com/api/v2/tiny/profile' -Headers $header
#$prof.result.profile
$outPath = $conf.outPath
if ($outpath -notmatch '\\$') {$outpath = $ooutpath + '\'}
$pwd = Resolve-Path ((Get-Location).path + '\TagLibSharp.dll')
if ($conf.format -eq '3') {$format = 'flac'}
elseif ($conf.format -eq '2') {$format = 'high'}
elseif ($conf.format -eq '1') {$format = 'mid'}

$streamURI = 'https://zvuk.com/api/tiny/track/stream'
$lyrURI = 'https://zvuk.com/api/tiny/musixmatch/lyrics'
#$albumURI = 'https://zvuk.com/api/tiny/releases'
#$plistURI = 'https://zvuk.com/api/tiny/playlists'
#$trackURI = 'https://zvuk.com/api/tiny/tracks'

'loading LibSharp lib'
[Reflection.Assembly]::LoadFrom(($pwd))|out-null

$links = $links -split ','|foreach {$_ -replace '\s'}
foreach ($link in $links) {
    if (!($link)) {
        $link = read-host 'insert Zvuk link'
    }

    $reqID = $link -split '/'|select -Last 1

    if ($link -match '\/release\/') {
        'getting info about album'
        #$albumLink = read-host 'insert album link'
        $reqBody = @{'ids' = $reqID;'include' = 'track,'}
        $reqURL = 'https://zvuk.com/api/tiny/releases'
        $downType = 'releases'
    }
    elseif ($link -match '\/playlist\/') {
        'getting info about playlist'
        #$albumLink = read-host 'insert album link'
        $reqBody = @{'ids' = $reqID;'include' = 'track,release,'}
        $reqURL = 'https://zvuk.com/api/tiny/playlists'
        $downType = 'playlists'
    }
    elseif ($link -match '\/track\/') {
        'getting info about track'
        #$albumLink = read-host 'insert album link'
        $reqBody = @{'ids' = $reqID;'include' = 'track,release,'}
        $reqURL = 'https://zvuk.com/api/tiny/tracks'
        $downType = 'tracks'
    }

    try {
        $downList = Invoke-RestMethod -uri $reqURL -Headers $header -Body $reqBody
    }
    catch {
        if ($_.Exception -match 'Unauthorized') {
            write-host 'Wrong creds or token' -foregroundcolor RED
            break
        }
    }
    if ($downType -eq 'playlists' -or $downType -eq 'releases') {$trackIDs = $downList.result.$downType.$reqID.track_ids}
    else {$trackIDs = $downList.result.$downType.$reqID.id}

    $i = 1
    foreach ($trackID in $trackIDs) {
        $track = $downList.result.tracks.psobject.Properties|?{$_.value.id -eq $trackID }
        $err = ''
        $body = @{}
        $id = $trackID
        $albumID = $track.value.release_id
		$plistID = $reqID
        $albumArtist = $downList.result.releases.$albumID.artist_names|select -first 1
        $year = $downList.result.releases.$albumID.date -replace '(^\d{4}).+','$1'
        $trackTitle = $track.value.title
        $artists = $track.value.artist_names
        $albumName = $track.value.release_title
        $genres = $track.value.genres
        $trackNumber = $track.value.position.toString("00")
        if ($downType -eq 'releases') {
            $baseFilename = $trackNumber + ' - ' + $trackTitle
			$albumArtist = $albumArtist -replace "[$([RegEx]::Escape([string][IO.Path]::GetInvalidFileNameChars()))]+","_"
			$year = $year -replace "[$([RegEx]::Escape([string][IO.Path]::GetInvalidFileNameChars()))]+","_"
			$albumName = $albumName -replace "[$([RegEx]::Escape([string][IO.Path]::GetInvalidFileNameChars()))]+","_"
            $downPath = $outPath + $albumArtist + '\' + $year + ' - ' + $albumName
        }
        elseif ($downType -eq 'playlists') {
            $position = $i.toString("000")
            $baseFilename = $position + ' - ' + $artists[0] + ' - ' + $trackTitle  + ' - ' + $albumName
            $plistName = $downList.result.playlists.$plistID.title
			$plistName = $plistName -replace "[$([RegEx]::Escape([string][IO.Path]::GetInvalidFileNameChars()))]+","_"
			'Title: ' + $plistName
            $downPath = $outPath + '_plists\' + $plistName
            $i ++
        }
        elseif ($downType -eq 'tracks') {
            $baseFilename = $artists[0] + ' - ' + $trackTitle  + ' - ' + $albumName
            $downPath = $outPath + '_tracks\'
        }
        $hasFLAC = $track.value.has_flac
        if ($format -eq 'flac' -and $hasFLAC -eq $true) {
            $body = @{'id' = $id;'quality' = 'flac'}
            $getFormat = 'FLAC'
            $filename = $baseFilename + '.flac'
        }
        elseif (($format -eq 'flac' -and $conf.formatFallback -eq $true) -or $format -eq 'high') {
                $body = @{'id' = $id;'quality' = 'high'}
                $getFormat = 'MP3'
                $filename = $baseFilename + '.mp3'
        }
        elseif (($format -eq 'high' -and $conf.formatFallback -eq $true) -or $format -eq 'mid') {
                $body = @{'id' = $id;'quality' = 'mid'}
                $getFormat = 'MP3'
                $filename = $baseFilename + '.mp3'
        }
        #$filename = $filename  -replace '[\,\/\\\[\]\(\)\:\;\?\!\@\<\>\%\+\"\|\*\"]','_'
		$filename = $filename -replace "[$([RegEx]::Escape([string][IO.Path]::GetInvalidFileNameChars()))]+","_"

		

        if (!(Test-Path $downPath)) {
            "`ncreating dir..."
            (New-Item -ItemType Directory $downPath).Fullname
            ''
        }
        if ($body.id) {
            "`ngetting file info " + $baseFilename + ' (' + $getFormat + ')'
            $lyrBody = @{'track_id' = $id}
            $ii = 0
            do {
                try {
                    $url = (Invoke-RestMethod -uri $streamURI -Headers $header -Body $body).result.stream
                    break
                }
                catch {
                    if ($_.Exception -match '\(418\)') {
                        $err = $_.Exception
                        $url = ''
                        Write-Host 'Error 418. Retrying...' -ForegroundColor RED
                    }
                    sleep 3
                }
                $ii ++
            } while ($err -ne '' -and $ii -lt 5)
            if ($conf.lyrics -eq $true) {
                $lyrReq = ''
                'getting lyrics...'
                do {
                    try {
                        $lyrReq = Invoke-RestMethod -uri $lyrURI -Headers $header -Body $lyrBody
                        break
                    }
                    catch {
                        if ($_.Exception -match '\(418\)') {
                            $err = $_.Exception
                            $url = ''
                            Write-Host 'Error 418. Retrying...' -ForegroundColor RED
                        }
                        sleep 3
                    }
                    $ii ++
                } while ($err -ne '' -and $ii -lt 5)
            }
            $fullName = $downPath + '\' + $filename
            'Downloading file...'
            Start-BitsTransfer -Source $url -Destination $fullName
            'saved file ' + $fullName
            'writing metadata...'
            $file = gci $fullName
            try {
                $afile = [TagLib.File]::Create(($file.FullName))
            }
            catch {
                if ($_.Exception -match 'MPEG') {
                        $newFullname = (join-path $file.Directory.FullName -ChildPath $file.BaseName) + '.flac'
                        Rename-Item $file.FullName -NewName $newFullname
                }
                elseif ($_.Exception -match 'FLAC') {
                    $newFullname = (join-path $file.Directory.FullName -ChildPath $file.BaseName) + '.mp3'
                    Rename-Item $file.FullName -NewName $newFullname
                }
                $afile = [TagLib.File]::Create(($newFullname))
            }
            $afile.tag.year = $year
            if ($afile.MimeType -match 'flac') {
                $afile.tag.Artists = $artists
                $afile.tag.Genres = $genres
            }
            elseif ($afile.MimeType -match 'mp3') {
                $afile.tag.Artists = ($artists -join ' ; ') -split ';'
                $afile.tag.Genres = ($genres -join ' ; ')
            }
            $afile.tag.Album = $albumName
            $afile.tag.AlbumArtists = $albumartist
            $afile.tag.Title = $trackTitle
            $afile.tag.Track = $trackNumber
            if ($conf.lyrics -eq $true -and $lyrReq.result.lyrics -ne '') {$afile.Tag.Lyrics = $lyrReq.result.lyrics}
            try {
				$client = new-object System.Net.WebClient
				$coverLink = 'https://cdn52.zvuk.com/pic?type=release&id=' + $albumID  + '&ext=jpg'
				$local_bin= $downPath + '\cover_max.jpg'
				$client.DownloadFile($coverLink, $local_bin)
				$coverLink = 'https://cdn52.zvuk.com/pic?type=release&id=' + $albumID + '&size=' + $conf.maxcover + '&ext=jpg'
				$local_bin2= $downPath + '\cover.jpg'
				$client.DownloadFile($coverLink, $local_bin)
            }
            #catch {if ($_.Exception) {rm $env:TEMP\cover.jpg}}
			catch {if ($_.Exception) {rm $downPath\cover.jpg}}
            #$afile.Tag.Pictures = [taglib.picture]::createfrompath("$env:TMP\cover.jpg")
			if (Test-Path [$downPath\cover.jpg]) {$afile.Tag.Pictures = [taglib.picture]::createfrompath("$downPath\cover.jpg")} 
			else {$afile.Tag.Pictures = [taglib.picture]::createfrompath("$downPath\cover_max.jpg")}
            #$afile.Tag.Pictures = [taglib.picture]::createfrompath("$downPath\cover_max.jpg")
            #$afile.Tag.Pictures = [taglib.picture]::createfrompath("$downPath\cover.jpg")
            $afile.save()
			
        }
        sleep 1
    }
    if ($links.count -gt 1) {
        'wait 5 secs till go to next link...'
        sleep 5

    }
}
