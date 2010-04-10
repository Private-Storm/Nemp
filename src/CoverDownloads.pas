{

    Unit CoverDownloads

    Class TCoverDownloadWorkerThread
        A Workerthread for downloading Covers from LastFM using its API

    ---------------------------------------------------------------
    Nemp - Noch ein Mp3-Player
    Copyright (C) 2009, Daniel Gaussmann
    http://www.gausi.de
    mail@gausi.de
    ---------------------------------------------------------------
    This program is free software; you can redistribute it and/or modify it
    under the terms of the GNU General Public License as published by the
    Free Software Foundation; either version 2 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful, but
    WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
    or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License
    for more details.

    You should have received a copy of the GNU General Public License along
    with this program; if not, write to the Free Software Foundation, Inc.,
    51 Franklin St, Fifth Floor, Boston, MA 02110, USA

    Additional permissions

    If you modify this Program, or any covered work, by linking or combining it
    with
        - the bass.dll and it addons
          (including, but not limited to the bass_fx.dll)
        - MadExcept
        - DGL-OpenGL
        - FSPro Windows 7 Taskbar Components
    or a modified version of these libraries, the licensors of this Program
    grant you additional permission to convey the resulting work.

    ---------------------------------------------------------------
}
unit CoverDownloads;

interface

uses
  Windows, Messages, SysUtils,  Classes, Graphics,
  Dialogs, StrUtils, ContNrs, Jpeg, PNGImage, GifImg, math, DateUtils,
  IdBaseComponent, IdComponent, IdTCPConnection, IdTCPClient, IdHTTP, IdStack, IdException,
  CoverHelper, MP3FileUtils, ID3v2Frames, AudioFileClass, Nemp_ConstantsAndTypes;

const
    ccArtist     = 0;
    ccAlbum      = 1;
    ccDirectory  = 2;
    ccQueryCount = 3;
    ccLastQuery  = 4;
    ccDataEnd    = 255;

type

    TPicType = (ptNone, ptJPG, ptPNG);

    TQueryType = (qtCoverFlow, qtPlayer);

    TCoverDownloadItem = class
        Artist: String;
        Album: String;
        Directory: String;
        QueryType: TQueryType;
        Index: Integer;         // used in CoverFlow
        distance: Integer;      // distance to MostImportantIndex
        lastChecked: TDateTime; // time of last query for this Item
        queryCount: Integer;    // Used to increase the Cache-Interval

        procedure LoadFromStream(aStream: TStream); // loading/saving in Thread-Context
        procedure SaveToStream(aStream: TStream);
    end;


    TCoverDownloadWorkerThread = class(TThread)
        private
            { Private-Deklarationen }
            fSemaphore: THandle;
            fIDHttp: TIdHttp;

            // Thread-Copy for the Item that is currently processed
            fCurrentDownloadItem: TCoverDownloadItem;
            fCurrentDownloadComplete: Boolean;

            // LastFM allows only 5 calls per Second
            // The GetTag-Method will be calles very often - so we need a speed-limit here!
            fLastCall: DWord;

            fJobList: TObjectList;   // Access only from VCL !!!

            fXMLData: AnsiString;        // API-Response
            fBestCoverURL: AnsiString;   // URL of the "extra-large" cover, if available
            fDataStream: TMemoryStream;  // Stream containing the Picture-Data
            fDataType: TPicType;

            fCacheFilename: String;
            fCacheList: TObjectList;

            fMostImportantIndex: Integer;
            procedure SetMostImportantIndex(Value: Integer);    // VCL


            // Thread-methods. Downloading, parsing, ...
            function QueryLastFMCoverXML: Boolean;
            function GetBestCoverUrlFromXML: Boolean;
            function DownloadBestCoverToStream: Boolean;
            // CacheList
            procedure LoadCacheList;
            procedure SaveCacheList;

            function GetMatchingCacheItem: TCoverDownloadItem;
            function CacheItemCanBeRechecked(aCacheItem: TCoverDownloadItem): Boolean;


            // VCL-methods
            function StreamToBitmap(TargetBMP: TBitmap): Boolean;

            procedure StartWorking;  // VCL

            // Get next job, i.e. information about the next queried cover
            procedure SyncGetFirstJob; // VCL
            // Update the Cover in Coverflow (or: in Player?)
            procedure SyncUpdateCover; // VCL



        protected
            procedure Execute; override;

        public
            property MostImportantIndex: Integer read fMostImportantIndex write SetMostImportantIndex;

            constructor Create;
            destructor Destroy; override;

            procedure AddJob(aCover: TNempCover; Idx: Integer); overload;     // VCL
            procedure AddJob(aAudioFile: TAudioFile; Idx: Integer); overload; // VCL
    end;

    function SortDownloadPriority(item1,item2: Pointer): Integer;

implementation

uses NempMainUnit, ScrobblerUtils, Hilfsfunktionen, SystemHelper;


function SortDownloadPriority(item1,item2: Pointer): Integer;
begin
    result := CompareValue(TCoverDownloadItem(item1).Distance, TCoverDownloadItem(item2).Distance);
end;

{ TCoverDownloadItem }


{
    --------------------------------------------------------
    LoadFromStream:
    - Load a CacheItem from a Stream
      String information is stored as UTF8
    --------------------------------------------------------
}
procedure TCoverDownloadItem.LoadFromStream(aStream: TStream);
var c: Integer;
    id: Byte;

        function ReadTextFromStream: String;
        var len: Integer;
            tmputf8: UTF8String;
        begin
            aStream.Read(len,sizeof(len));
            setlength(tmputf8, len);
            aStream.Read(PAnsiChar(tmputf8)^, len);
            result := UTF8ToString(tmputf8);
        end;

begin
    c := 0;
    repeat
        aStream.Read(id, sizeof(ID));
        inc(c);
        case ID of
            ccArtist     : Artist := ReadTextFromStream;
            ccAlbum      : Album  := ReadTextFromStream;
            ccDirectory  : Directory  := ReadTextFromStream;
            ccQueryCount : aStream.Read(queryCount, SizeOf(queryCount));
            ccLastQuery  : aStream.Read(lastChecked, SizeOf(LastChecked));
            ccDataEnd    : ;  // Nothing to do
        else
            ID := ccDataEnd;  // Somthing was wrong, abort
        end;
    until (ID = ccDataEnd) or (c >= ccDataEnd);
end;
{
    --------------------------------------------------------
    SaveToStream:
    - Save the data
      String information is stored as UTF8
    --------------------------------------------------------
}
procedure TCoverDownloadItem.SaveToStream(aStream: TStream);
var ID: Byte;

        procedure WriteTextToStream(ID: Byte; wString: UnicodeString);
        var len: integer;
            tmpStr: UTF8String;
        begin
            aStream.Write(ID,sizeof(ID));
            tmpstr := UTF8Encode(wString);
            len := length(tmpstr);
            aStream.Write(len,SizeOf(len));
            aStream.Write(PAnsiChar(tmpstr)^,len);
        end;

begin
    WriteTextToStream(ccArtist   , Artist);
    WriteTextToStream(ccAlbum    , Album );
    WriteTextToStream(ccDirectory, Directory);

    ID := ccQueryCount;
    aStream.Write(ID, sizeof(ID));
    aStream.Write(QueryCount, sizeOf(QueryCount));

    ID := ccLastQuery;
    aStream.Write(ID, sizeof(ID));
    aStream.Write(lastChecked, sizeOf(lastChecked));

    ID := ccDataEnd;
    aStream.Write(ID, sizeof(ID));
end;


{ TCoverDownloadWorkerThread }

constructor TCoverDownloadWorkerThread.Create;
begin
    inherited create(True);
    fIDHttp := TIdHttp.Create;
    fJobList := TObjectList.Create;
    fDataStream := TMemoryStream.Create;
    fCurrentDownloadItem := TCoverDownloadItem.Create;
    fSemaphore := CreateSemaphore(Nil, 0, maxInt, Nil);
    FreeOnTerminate := False;

    fIDHttp.ConnectTimeout:= 5000;
    fIDHttp.ReadTimeout:= 5000;
    fIDHttp.Request.UserAgent := 'Mozilla/3.0';
    fIDHttp.HTTPOptions :=  [];

    Resume;
end;

destructor TCoverDownloadWorkerThread.Destroy;
begin
    fIDHttp.Free;
    fDataStream.Free;
    fJobList.Free;
    fCurrentDownloadItem.Free;
    inherited;
end;

procedure TCoverDownloadWorkerThread.Execute;
var n: DWord;
    CurrentCacheItem: TCoverDownloadItem;
    NewCacheItem: TCoverDownloadItem;

begin
    // LoadCacheList
    fCacheList := TObjectList.Create;

    if AnsiStartsText(GetShellFolder(CSIDL_PROGRAM_FILES), Paramstr(0)) then
        fCacheFilename := GetShellFolder(CSIDL_APPDATA) + '\Gausi\Nemp\CoverCache'
    else
        fCacheFilename := ExtractFilePath(ParamStr(0)) + 'Data\CoverCache';

    LoadCacheList;

    try
        While Not Terminated do
        begin
            if (WaitforSingleObject(fSemaphore, 1000) = WAIT_OBJECT_0) then
            if not Terminated then
            begin
                Synchronize(SyncGetFirstJob);
                if assigned(fCurrentDownloadItem) then
                begin

                    // Check, for Cache-time here
                    // get Item in CacheList

                    CurrentCacheItem := GetMatchingCacheItem;
                    if CacheItemCanBeRechecked(CurrentCacheItem) then
                    begin
                        n := GetTickCount;
                        if n - fLastCall < 250 then
                            sleep(250);
                        fLastCall := GetTickCount;

                        // we start the dwonload now
                        fCurrentDownloadComplete := False;

                        QueryLastFMCoverXML;
                        GetBestCoverUrlFromXML;
                        DownloadBestCoverToStream;     // here: Download ok (or not)

                        Synchronize(SyncUpdateCover);  // after this: Cover is really ok


                        if fCurrentDownloadComplete then // is set to True in SyncUpdateCover
                        begin
                            if assigned(CurrentCacheItem) then
                                fCacheList.Remove(CurrentCacheItem)

                                // Synchronize(ChangeCoverFlow)
                                ///  Cover in Datei "front (NEMPAutoCover).xxx" schreiben
                                ///  MD5 vom Cover bestimmen und in Cover-Ordner kopieren
                                !!!!!!!
                                ///  passendes NempCover finden
                                ///  AudioFileListe generieren
                                ///  Neue ID setzen

                        end else
                        begin
                            // the current job was not completed
                            if assigned(CurrentCacheItem) then
                            begin
                                // the job was already in the cache-list
                                // increase Counter and save queryTime
                                CurrentCacheItem.queryCount := CurrentCacheItem.queryCount + 1;
                                CurrentCacheItem.lastChecked := Now;
                            end else
                            begin
                                NewCacheItem := TCoverDownloadItem.Create;
                                NewCacheItem.Artist := fCurrentDownloadItem.Artist;
                                NewCacheItem.Album  := fCurrentDownloadItem.Album ;
                                NewCacheItem.Directory := fCurrentDownloadItem.Directory;
                                NewCacheItem.queryCount := 1;
                                NewCacheItem.lastChecked := Now;

                                fCacheList.Add(NewCacheItem);
                            end;
                        end;
                    end;
                end;
            end;
        end;
        SaveCacheList;
    finally
        fCacheList.Free;
    end;
end;

{
    --------------------------------------------------------
    LoadCacheList:
    - Load the Cache from the CacheFile
      Store the CoverDownloadItems in the Target-List
    --------------------------------------------------------
}
procedure TCoverDownloadWorkerThread.LoadCacheList;
var Header: AnsiString;
    major,minor: Byte;
    aStream: TMemoryStream;
    i, Count: Integer;
    NewItem: TCoverDownloadItem;
begin
    aStream := TMemoryStream.Create;
    try
        if FileExists(fCacheFilename) then
        begin
            aStream.LoadFromFile(fCacheFilename);
            aStream.Position := 0;

            SetLength(Header, Length('NempCoverCache'));
            aStream.Read(Header[1], length(Header));
            aStream.Read(major, sizeOf(Byte));
            aStream.Read(minor, sizeOf(Byte));

            if (Header = 'NempCoverCache')
                and (major = 1)
                and (minor = 0)
            then
            begin
                aStream.Read(Count, SizeOf(Count));
                for i := 0 to Count - 1 do
                begin
                    NewItem := TCoverDownloadItem.Create;
                    NewItem.LoadFromStream(aStream);
                    fCacheList.Add(NewItem);
                end;
            end;
        end;
    finally
        aStream.Free;
    end;
end;

procedure TCoverDownloadWorkerThread.SaveCacheList;
var Header: AnsiString;
    major,minor: Byte;
    aStream: TMemoryStream;
    i, Count: Integer;
begin
    aStream := TMemoryStream.Create;
    try
        Header := 'NempCoverCache';
        major  := 1;
        minor  := 0;
        Count  := fCacheList.Count;

        aStream.Write(Header[1], length(Header));
        aStream.Write(major, sizeOf(Byte));
        aStream.Write(minor, sizeOf(Byte));

        aStream.Write(Count, SizeOf(Count));

        for i := 0 to Count - 1 do
            TCoverDownloadItem(fCacheList[i]).SaveToStream(aStream);

        aStream.SaveToFile(fCacheFilename);
    finally
        aStream.Free;
    end;
end;


{
    --------------------------------------------------------
    GetMatchingCacheItem:
    - Search an Item in the Cache-List, which matches Self.fCurrentDownloadItem
    --------------------------------------------------------
}
function TCoverDownloadWorkerThread.GetMatchingCacheItem: TCoverDownloadItem;
var i: Integer;
    aItem: TCoverDownloadItem;
begin
    result := Nil;
    for i := 0 to fCacheList.Count - 1 do
    begin
        aItem := TCoverDownloadItem(fCacheList[i]);
        if (aItem.Artist = fCurrentDownloadItem.Artist)
            and (aItem.Album = fCurrentDownloadItem.Album)
        then
        begin
            result := aItem;
            break;
        end;
    end;
end;

{
    --------------------------------------------------------
    CacheItemCanBeRechecked:
    - Check, whether a new Request for this item does make sense
      i.e. last check is some time ago
    --------------------------------------------------------
}
function TCoverDownloadWorkerThread.CacheItemCanBeRechecked(
  aCacheItem: TCoverDownloadItem): Boolean;
begin
    result :=
        (not assigned(aCacheItem))
        or
        (
            (DaysBetween(now, aCacheItem.lastChecked) >= 7) // one week ago
            or
            // one day ago and not very often tested yet (better for brandnew albums?)
            ((HoursBetween(now, aCacheItem.lastChecked) >= 24) and (aCacheItem.queryCount <= 10))
        );
end;

{
    --------------------------------------------------------
    QueryLastFMCoverXML:
    - download the XML-Reply from the LastFM API
      save the reply in Self.fXMLData
    --------------------------------------------------------
}
function TCoverDownloadWorkerThread.QueryLastFMCoverXML: Boolean;
var url: UTF8String;
begin

    url := 'http://ws.audioscrobbler.com/2.0/?method=album.getinfo'
        + '&api_key=' + api_key
        + '&artist=' + StringToURLStringAnd(AnsiLowerCase(fCurrentDownloadItem.Artist))
        + '&album='  + StringToURLStringAnd(AnsiLowerCase(fCurrentDownloadItem.Album));
    try
        fXMLData := fIDHttp.Get(url);
        result := True;
    except
        on E: Exception do
        begin
          fXMLData := E.Message;
          result := False;
        end;
    end;
end;

{
    --------------------------------------------------------
    GetBestCoverUrlFromXML:
    - Parse the fXMLData and get a Cover URL
      save the URL in Self.fBestCoverURL
    --------------------------------------------------------
}
function TCoverDownloadWorkerThread.GetBestCoverUrlFromXML: Boolean;
var s, e: Integer;
    offset: Integer;
begin
    s := Pos('<image size="extralarge">', fXMLData);
    offset := length('<image size="extralarge">');

    if s = 0 then
    begin
        s := Pos('<image size="large">', fXMLData);
        offset := length('<image size="large">');
    end;

    if s > 0 then
    begin
        e := PosEx('</image>', fXMLData, s);
        fBestCoverURL := Copy(fXMLData, s + offset, e - (s + offset));
        result := True;
    end else
    begin
        result := False;
        fBestCoverURL := '';
    end;
end;



{
    --------------------------------------------------------
    DownloadBestCoverToStream:
    - Download Cover from fBestCoverURL
    --------------------------------------------------------
}
function TCoverDownloadWorkerThread.DownloadBestCoverToStream: Boolean;
begin
    if fBestCoverURL <> '' then
    begin
        fDataStream.Clear;
        try
            fIDHttp.Get(fBestCoverURL, fDataStream);
        except
            fDataStream.Clear;
            result := False;
            fDataType := ptNone;
        end;

        if AnsiEndsText('.jpg', fBestCoverURL) then
            fDataType := ptJPG
        else
        if AnsiEndsText('.png', fBestCoverURL) then
            fDataType := ptPNG
        else
        if AnsiEndsText('.jpeg', fBestCoverURL) then
            fDataType := ptJPG
        else
            fDataType := ptNone;
    end else
    begin
        result := False;
        fDataType := ptNone;
        fDataStream.Clear;
    end;
end;

{
    --------------------------------------------------------
    StreamToBitmap:
    - Load StreamData into the Bitmap.
      VCL-THREAD ONLY !!!
    --------------------------------------------------------
}
function TCoverDownloadWorkerThread.StreamToBitmap(TargetBMP: TBitmap): Boolean;
var jp: TJPEGImage;
    png: TPNGImage;
    localBMP: TBitmap;
begin
    localBMP := TBitmap.Create;
    try
        case fDataType of
            ptNone: begin
                result := False;
                // nothing mor to do. Unknown Picture-Data :(
            end;
            ptJPG: begin
                fDataStream.Seek(0, soFromBeginning);
                jp := TJPEGImage.Create;
                try
                    try
                        jp.LoadFromStream(fDataStream);
                        jp.DIBNeeded;
                        localBMP.Assign(jp);
                        SetStretchBltMode(TargetBMP.Canvas.Handle, HALFTONE);
                        StretchBlt(TargetBMP.Canvas.Handle, 0 ,0, TargetBMP.Width, TargetBMP.Height,
                                   localBMP.Canvas.Handle, 0, 0, localBMP.Width, localBMP.Height, SRCCopy);
                        result := True;
                    except
                        result := False;
                        TargetBMP.Assign(NIL);
                    end;
                finally
                    jp.Free;
                end;
            end;
            ptPNG: begin
                fDataStream.Seek(0, soFromBeginning);
                png := TPNGImage.Create;
                try
                    try
                        png.LoadFromStream(fDataStream);
                        localBMP.Assign(png);
                        SetStretchBltMode(TargetBMP.Canvas.Handle, HALFTONE);
                        StretchBlt(TargetBMP.Canvas.Handle, 0 ,0, TargetBMP.Width, TargetBMP.Height,
                                   localBMP.Canvas.Handle, 0, 0, localBMP.Width, localBMP.Height, SRCCopy);
                        result := True;
                    except
                        result := False;
                        TargetBMP.Assign(NIL);
                    end;
                finally
                    png.Free;
                end;
            end;
        end;
    finally
        localBMP.Free;
    end;
end;

{
    --------------------------------------------------------
    AddJob: Called from the VCL
    VCL-THREAD ONLY !!!
    --------------------------------------------------------
}
procedure TCoverDownloadWorkerThread.AddJob(aCover: TNempCover; Idx: Integer);
var NewDownloadItem: TCoverDownloadItem;
begin
    NewDownloadItem := TCoverDownloadItem.Create;
    NewDownloadItem.Artist    := aCover.Artist;
    NewDownloadItem.Album     := aCover.Album;
    NewDownloadItem.Directory := aCover.Directory;
    NewDownloadItem.QueryType := qtCoverFlow;
    NewDownloadItem.Index     := Idx;
    fJobList.Insert(0, NewDownloadItem);
    if fJobList.Count > 50 then
        fJobList.Delete(fJobList.Count-1);

    StartWorking;
end;

procedure TCoverDownloadWorkerThread.AddJob(aAudioFile: TAudioFile;
  Idx: Integer);
var NewDownloadItem: TCoverDownloadItem;
begin
    NewDownloadItem := TCoverDownloadItem.Create;
    NewDownloadItem.Artist    := aAudioFile.Artist;
    NewDownloadItem.Album     := aAudioFile.Album;
    NewDownloadItem.Directory := aAudioFile.Ordner;
    NewDownloadItem.QueryType := qtPlayer;
    NewDownloadItem.Index     := 0;

    fJobList.Insert(0, NewDownloadItem);
    if fJobList.Count > 50 then
        fJobList.Delete(fJobList.Count-1);

    StartWorking;
end;

procedure TCoverDownloadWorkerThread.StartWorking;
begin
    ReleaseSemaphore(fSemaphore, 1, Nil);
end;

{
    --------------------------------------------------------
    SetMostImportantIndex
    - Used to download centered Covers in the Coverflow first
      called from CoverFlow.SetcurrentItem
    VCL-THREAD ONLY !!!
    --------------------------------------------------------
}
procedure TCoverDownloadWorkerThread.SetMostImportantIndex(Value: Integer);
var i: Integer;
    aDownloadItem: TCoverDownloadItem;

begin
    if fMostImportantIndex <> Value then
    begin
        fMostImportantIndex := Value;
        for i := 0 to fJobList.Count - 1 do
        begin
            aDownloadItem := TCoverDownloadItem(fJobList[i]);
            aDownloadItem.distance := abs(aDownloadItem.Index - Value);
        end;
        fJobList.Sort(SortDownloadPriority);
    end;
end;


procedure TCoverDownloadWorkerThread.SyncGetFirstJob;
var fi: TCoverDownloadItem;
begin
    // result: True if there is something to do
    if fJobList.Count > 0 then
    begin
        // Copy the Item from the List, so the Thread can savely work on this
        fi := TCoverDownloadItem(fJobList.Items[0]);
        fCurrentDownloadItem.Artist      := fi.Artist    ;
        fCurrentDownloadItem.Album       := fi.Album     ;
        fCurrentDownloadItem.Directory   := fi.Directory ;
        fCurrentDownloadItem.Index       := fi.Index     ;
        fCurrentDownloadItem.QueryType   := fi.QueryType ;

        fJobList.Delete(0);
    end
    else
        fCurrentDownloadItem := Nil;
end;

procedure TCoverDownloadWorkerThread.SyncUpdateCover;
var bmp: TBitmap;
    r: TRect;
    s: String;
begin
    bmp := TBitmap.Create;
    try
        bmp.PixelFormat := pf24bit;

        bmp.Height := 240;
        bmp.Width := 240;

        fCurrentDownloadComplete := StreamToBitmap(bmp);
        //if not success then
        begin
            if self.fXMLData <> '' then
            begin
                bmp.Canvas.Font.Size := 6;
                r := Rect(0,0,240,10);
                s := fBestCoverURL;//fXMLData;
                bmp.Canvas.TextRect(r, s, [tfWordBreak]);
            end else
            begin
                bmp.Canvas.Font.Size := 16;
                bmp.Canvas.TextOut(10, 10, fCurrentDownloadItem.Artist);
                bmp.Canvas.TextOut(10, 80, fCurrentDownloadItem.Album);
            end;
        end;

        Medienbib.NewCoverFlow.SetPreview (fCurrentDownloadItem.Index, bmp.Width, bmp.Height, bmp.Scanline[bmp.Height-1]);

        MedienBib.NewCoverFlow.Paint(1);
    finally
        bmp.free;
    end;
end;



end.
