/*  
[INFO] 
NAME = ShotGrid Tools
VERSION = 1.0.0
AUTHOR = MastaMan
DEV = https://3dground.net
HELP = 
CLIENT=Eugen Zharnikov
[ABOUT]
Script for optimize workflow and send to render Wayfair models=

[1.0.0]
* Initial release =

[SCRIPT]
*/

/*************************************************/
-- VARIABLES
/*************************************************/

global urlAuth = @"https://partners.wayfair.com/v/tools3d/authentication/auth"
global urlGraphql = @"https://partners.wayfair.com/a/catalog_media/creative_tech/api/graphql"
global urlDownlodZip = @"https://mediaingestion.wayfair.com/download?assetId=$1&generationId="
global fileDownloadIni = "index.ini"

global wayfairLogin = "WadeWorks"
global wayfairPassword = "RMmodels12~3"


global shotGunFolderName = @"ShotGun\"

global _AUTH_ = undefined
global isNowDownloading = false
global completedDownloads = 0
global cancelDownload = false
global prevProgress = 0

/*************************************************/
-- GLOBAL FUNC
/*************************************************/

try(syncWorker2.Dispose()) catch()

fn getDownloadFolder p id = (
	return p + @"scenes\" + id + @"\"
)

fn putDownloadIni f k v = (
	p = (f + ::fileDownloadIni)	
	setINISetting p "INDEX" k v
)

fn readResponce r = (
	if (r == undefined) do return undefined
	
	s = r.GetResponseStream()
	sr = dotnetobject "System.IO.StreamReader" s
	return sr.ReadToEnd()			
)

fn parseString ss p1 p2 repl: #() = (
	z1 = findString ss p1
	if(z1 == undefined) do return z1
	
	z1 += p1.count
	
	ss = subString ss z1 -1
	
	z2 = findString ss p2
	if(z2 == undefined) do return z2
	k = subString ss 1 (z2 - 1)
	k = trimLeft (trimRight k)
	if(repl.count == 2) do k = substituteString k repl[1] repl[2]
	
	return k
)

fn postRequestData url postData: "" headers: #() cookies: "" refferer: "" method: "POST" forceContentType: "" forceAcceptType: "" = (	
	-- If post data is formData encoded (array)
	contentType = "application/json; charset=utf-8"	
	data = postData
	
	if (classOf postData == Array) then (
		contentType = "application/x-www-form-urlencoded"
		data = ""
		for i in 1 to postData.count do data += postData[i][1] + "=" + postData[i][2] + (if (i != postData.count) then "&" else "")
	)
	
	if (forceContentType.count > 0) do contentType = forceContentType
	
	w = (dotNetClass "System.Net.WebRequest").Create url
	w.Timeout = 15000
	
	try (
		-- Set TLS	
		spm = dotNetClass "System.Net.ServicePointManager"
		spm.SecurityProtocol = spm.SecurityProtocol.TLS12				
		
		-- Set settigns
		w.Method = method
		w.ContentType = contentType		
		w.UserAgent = "Mozilla/5.0"
		
		if (refferer.count > 0) do w.Referer = refferer
		if (forceAcceptType.count > 0) then (
			w.Accept = forceAcceptType
		) else (
			w.Accept = "text/html,application/json,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.9"
		)
		
		-- Set headers
		for i in headers do w.Headers.add i[1] i[2]
			
		-- Set Cookie
		if (cookies.count > 0) do (
			w.Headers.add "Cookie" cookies
		)
		
		j = w.GetRequestStream()
		b = (dotnetObject "System.Text.UTF8Encoding").GetBytes data
			
		j.Write b 0 b.count
		j.Close()
		
		r = w.GetResponse()
		
		return r
	) catch(
		print (">>> " + getCurrentException())
		return undefined
	)
		
	return undefined
)

fn readCookies r = (
	for i in 0 to r.Headers.Count - 1 do (		
		k = r.Headers.Keys[i]
		if (k == "Set-Cookie") do (
			v = r.Headers[i]
			return v
		)
	)
	
	return ""
)

fn readFileName r = (
	h = r.ResponseHeaders
	if(h == undefined) do return ""
	
	c = h.count
	
	for i in 0 to c - 1 do (
		t = h.item[i]			
		f = "filename="
		p = findString t f
		if(p == undefined) do continue
		t = subString t (p + f.count) -1
		return t
	)
	
	return ""
)

fn postAuth = (
	data = #(
		#("username", ::wayfairLogin),
		#("password", ::wayfairPassword),
		#("external", "true")
	)
	
	r = postRequestData ::urlAuth postData: data
	
	if (r == undefined) do return undefined
	
	-- Gather Set Cookies
	cookies = readCookies r
		
	-- Read Token
	o = readResponce r
	
	if (o == undefined or o[1] != "{") do return undefined
	
	token = ""
	tmp = parseString o ":\"" "\""			
	if (tmp.count > 10) do token = tmp	
	
	if (cookies.count < 2 or token.count < 10) do return undefined
		
	struct a (status, cookies, token)	
	return a status: true cookies: cookies token: token
)

-- Graphql takes all needed ids
fn postGraphql id = (
	local a = ::_AUTH_
	if (a == undefined) do return undefined
	
	-- 37418
	data = "{
				\"service_name\": \"cmedia-shotgun-create-service\",
				\"query\": \"query($shot_id: Int!) { getZiePayloadFromShot(shot_id: $shot_id) {status, template_id, model_id, mpid}}\",
				\"variables\": {
					\"shot_id\": " + (id as string) + "
				}
			}"
		
	r = postRequestData ::urlGraphql postData: data cookies: a.cookies
	o = readResponce r
	
	if (o == undefined or o[1] != "{") do return undefined
		
	template_id = parseString o "template_id\":\"" "\""
	model_id = parseString o "model_id\":\"" "\""
	mpid = parseString o "mpid\":\"" "\""
		
	if (template_id.count < 3 or model_id.count < 3 or mpid.count < 2) do return undefined
		
	struct g (template_id, model_id, mpid)
	return g template_id: template_id model_id: model_id mpid: mpid
)

fn boost = (
	if (((maxVersion())[1] / 1000) >= 13) do windows.processPostedMessages() 
)

fn formatString s v: #() tag: "$"= (
	for i in 1 to v.count  do (
		s = substituteString s (tag + i as string) (v[i] as string)
	)
	
	return s
)

fn getFileMb f = (
	s = (getFileSize f) / 1048576.0
	return ((s * 100) as integer) / 100.0
)

fn trimString s tag: "" = (
	s = s as string
	return (trimLeft (trimRight s tag) tag)
)

struct dateTime (
    n = (dotNetClass "System.DateTime").Now,
    y = n.year as string,
    d = n.day as string,
    m = n.month as string,
    hh = n.hour as string,
    mm = n.minute as string,
    ss = n.second as string
)

fn disable3DsMaxSecurity = (
	ini = getMaxIniFile()
	
	s = "Security"
	v = "0"
	p = #(
		"SafeSceneScriptExecutionEnabled",
		"EmbeddedMAXScriptSystemCommandsExecutionBlocked",
		"EmbeddedPythonExecutionBlocked",
		"EmbeddedDotNetExecutionBlocked",
		"ShowSecurityMessagesWindowOnBlockedCommandsEnabled",
		"ShowScriptEditorOnBlockedCommandsEnabled"
	)
	for k in p do setIniSetting ini s k v	
	
	s = "SecurityTools"
	v = "0"
	p = #(
		"LoadSecurityTools",
		"DisplayUpdateNotification"
	)
	for k in p do setIniSetting ini s k v		
)

disable3DsMaxSecurity()
SceneConverter.BackupOriginalFiles = false

global rShowLog
fn showLog m title:"Log" height: 300 width: 600 = (
    try(DestroyDialog rShowLog)catch()
    global szStat = m
    global iWidth = width - 2
    global iHeight = height - 35
    
    rollout rShowLog title
    (
        dotNetControl edtStat "System.Windows.Forms.Textbox" width: iWidth height: iHeight align:#center pos: [1, 1]
                
        dotNetControl btnCopyLog "System.Windows.Forms.Button" height: 25 width: 90 align: #left across: 2 
        dotNetControl btnCloseLog "System.Windows.Forms.Button" height: 25 width: 90 align: #right 
        
        fn initDotNet = (
            initTextBox edtStat
            btnCloseLog.text = "Close"
            btnCopyLog.text = "Copy"
			
            btnCloseLog.flatStyle = btnCloseLog.flatStyle.Popup
            btnCopyLog.flatStyle = btnCloseLog.flatStyle.Popup
        )
        
        on btnCloseLog Click do try(DestroyDialog rShowLog)catch()
        on btnCopyLog Click do setClipboardText szStat 
		
        on rShowLog open do (
            initDotNet()
            edtStat.text = szStat
        )
    )

    createDialog rShowLog width height
)

fn getLocalTimeName = (
	d = dateTime()
	
	return d.d + "_" + d.m + "_" + d.y + "___" + d.hh + "_" + d.mm + "_" + d.ss
)

fn getRender = (
	r = renderers.current as string

	if matchpattern r pattern:"*Corona*" do return #("corona", "Corona")
	if matchpattern r pattern:"*V_Ray*" do return #("vray", "VRay")
	if matchpattern r pattern:"*Default_Scanline*" do return #(" scanline", "Scanline")
	if matchpattern r pattern:"*mental_ray*" do return #("mentalray", "MentalRay")
	if matchpattern r pattern:"*iray_Renderer*" do return #("iray", "IRay")
	if matchpattern r pattern:"*maxwell*" do return #("maxwell", "Maxwell")
		
	return #("", "")
)

fn getOpenFiles filt: "Archives (*.zip) | *.zip"  = (
	f = #()
	
	imageDialog = dotNetObject "System.Windows.Forms.OpenFileDialog" 
	imageDialog.title = "Select Files"
	imageDialog.Multiselect = true
	imageDialog.Filter = filt
	imageDialog.FilterIndex = 1
	
	r = imageDialog.showDialog() 
	r.ToString()
	r.Equals r.OK
	r.Equals r.Cancel
	
	f = imageDialog.fileNames 
	 
	return f
)

fn freezeUi = (
    source = ""
    source += "using System;\n"
    source += "using System.Runtime.InteropServices;\n"
    source += "class WindowsGhosting\n"
    source += "{\n"
    source += " [DllImport(\"user32.dll\")]\n"
    source += " public static extern void DisableProcessWindowsGhosting();\n"
    source += "}\n"
  
    csharpProvider = dotnetobject "Microsoft.CSharp.CSharpCodeProvider"
    compilerParams = dotnetobject "System.CodeDom.Compiler.CompilerParameters"
  
    compilerParams.GenerateInMemory = on
    compilerResults = csharpProvider.CompileAssemblyFromSource compilerParams #(source)
  
    assembly = compilerResults.CompiledAssembly
    windowsGhosting = assembly.CreateInstance "WindowsGhosting"
    windowsGhosting.DisableProcessWindowsGhosting()
)

freezeUi()

struct '@' (
	ini = (getFileNamePath (getThisScriptFileName())) + @"settings\ShotGrid Tools@" +  sysinfo.username + "@" + sysinfo.computername + ".ini",
	--ini = (getThisScriptFileName()) + ".ini",
	sec = "SETTINGS",
	fn add k v = (
		setIniSetting this.ini this.sec k (v as string)
	),
	fn get k type: #string = (
		v = getIniSetting this.ini this.sec k
		
		case type of (
			#bool: return if(v == "true") then true else false
			#int: return try (v as integer) catch(0)
		)
		
		return v
	),
	fn trim s tag: "" = (
		s = s as string
		return (trimLeft (trimRight s tag) tag)
	)
)

global '*' = '@'()

fn loadFileAsArray o = (
	local f = openFile o
	local b = #()

	while (not eof f) do (
		l = readline f				
		append b l
	)
	flush f
	close f
	
	return b
)

/*************************************************/
-- ROLLOUTS
/*************************************************/

global _rStepBatchDownloads
global _rSettings
global _rAboutSGT

global rolloutsState = #(undefined, undefined, undefined, undefined, undefined)

fn sliderStep n x = (
	try(
		if(rolloutsState[n] == undefined) do (
			rolloutsState[n] = x
			return false
		)
		
		k = #(_rStepBatchDownloads, _rSettings, _rAboutSGT)
		
		for i in k where i.open == true and i != k[n] do i.open = false
		
		
		k[n].open = x
	) catch()
)

try(cui.UnRegisterDialogBar floaterShotGunTools) catch()
try(closeRolloutFloater floaterShotGunTools)catch()
try(closeRolloutFloater floaterShotGunTools) catch()
global floaterShotGunTools = newRolloutFloater "ShotGun Tools" 300 720

rollout _rStepBatchDownloads  "Downloader" (
	global TASK_LIST = #()
	global PATH_LIST = #()
	global downloadIdsList = #()
	global qeueDownloadList = #()
	
	group "Parse Files" (
		label lblTaskFile "Task.csv" align: #left
		edittext edtTaskFile "" readonly: true across: 2 align: #left fieldwidth: 215 height: 22		
		button btnSearchTaskFile "..." width: 35 height: 24  align: #right offset: [0, -1]
		
		label lblPathsFile "PathName.csv" align: #left
		edittext edtPathsFile "" readonly: true across: 2 align: #left fieldwidth: 215 height: 22		
		button btnSearchPathsFile "..." width: 35 height: 24  align: #right offset: [0, -1]      
	)
	
	timer tmrLoad "" active: false interval: 150
	
	group "Batch Downloads" (
		dropdownlist ddlRemoteUsers "Users List:" items: #("")
		
		label lblUserAssigneSKUCaption "User Assigned SKU" align: #left across: 2
		label lblUserAssigneSKUCnt ": (0)" align: #left across: 2 offset: [-38, 0]
		
		label lblSelectedFor "Selected for Download " align: #left across: 2
		label lblSelectedForCnt ": (0)" align: #left across: 2 offset: [-23, 0]
		
		multiListBox lbxRemoteIds "" items: #()	
		
		button btnSelectAll "Select All" width: 100 across: 2
		button btnDeselectAll "Deselect All" width: 100
		
		label lblRemoteFolderCaption "Folder: " align: #left across: 2 offset: [0, 10]
		--label lblRemoteFolder "?" align: #left offset: [-90, 10]
		HyperLink lblRemoteFolder "?" enabled: false color: orange hoverColor: orange visitedColor: orange address: ""  align: #left offset: [-90, 10]
				
		button btnStartBatchDownload "Download" width: 260 height: 28 enabled: false offset: [0, 10]
		progressBar pbDownload "" height: 6 color: orange
	)
	
	fn getUser = (
		id = ddlRemoteUsers.selection
		if(id == 0 or id == 1) do return ""
		return (ddlRemoteUsers.items[id])
	)
	
	fn simplifyPropName p = (
		p = substituteString p " " ""
		p = substituteString p ">" ""
		return p
	)
	
	fn stripValue v = (
		v = substituteString v @"\" @"\\"
		return v
	)
	
	fn getCSV_Ids t list: #() = (		
		ids = #()
		if (list.count == 0) do return #()
		
		for i in list do (
			id = findItem t i
			
			if (id != 0) do (
				append ids id					
				continue
			)
			
			append ids undefined
		)
		
		return ids
	)
	
	fn parseCSV f list: #() = (
		out = #()
		u = #()
		
		if (f == "") do return #()
		
		d = loadFileAsArray f
		
		if (d[1] == undefined or d[1] == "") do return #()
		
		t = for i in filterString d[1] "," collect trimString i tag: "\""		
		d = deleteItem d 1
		
		if (list.count == 0) do list = t
		
		ids = getCSV_Ids t list: list
		
		for b in d do (
			o = for i in filterString b "," collect trimString i tag: "\""	
			
			struct tmp (id)
			
			local s = "struct tmp ("
				for i in 1 to list.count do (
					n = list[i]
					s += simplifyPropName n + ","
				)
				s = trimRight s ","
			s += ")"
				
			execute(s)
			
			local s = "tmp "
			for i in 1 to list.count do (
				id = ids[i]
				if (id == undefined) do continue
				n = list[i]
				s += simplifyPropName n
				s += ":"
				s += "\"" + (stripValue o[id]) + "\" "					
			)
			s = trimRight s ","	
		
			append out (execute(s))
		)
		
		return out
	)
	
	fn getUniqueParamData d p: "" = (
		p = simplifyPropName p
		r = #()
		
		for i in d do (
			o = getProperty i p
			appendIfUnique r o
		)
		
		return r
	)
	
	fn getUserPath d u: "" p1: "Assigned To" p2: "path" = (
		if (d == undefined) do return undefined
		
		p1 = simplifyPropName p1
		p2 = simplifyPropName p2
		
		for i in d do (
			uu = getProperty i p1
			if (uu == u) do return ((getProperty i p2) + ::shotGunFolderName)
		)
		
		return undefined
	)
	
	fn parseTask f = (
		return parseCSV f list: #("Shot Id", "Status", "Assigned To", "Shot > Product > SKU") unique: #("AssignedTo")		
	)
	
	fn parsePath f = (
		return parseCSV f
	)
		
	fn loadUniqueUsers d p = (
		uu = getUniqueParamData d p: "Assigned To"
		
		r = #()
		
		for u in uu do (
			pp = getUserPath p u: u
			if (pp == undefined) then (
				append r ("[Path Not Found] " + u)
			) else (
				append r u
			)
		)
		
		o = #("")
		join o r
		
		ddlRemoteUsers.items = o
	)
	
	-- Load all settings from CSV
	fn loadSettings = (
		edtTaskFile.text = ""
		taskFile = '*'.get "TASK_FILE"
		if (taskFile != "" and doesFileExist taskFile) do edtTaskFile.text = taskFile
		
		edtPathsFile.text = ""
		pathFile = '*'.get "PATH_FILE"
		if (pathFile != "" and doesFileExist pathFile) do edtPathsFile.text = pathFile
		
		if (edtPathsFile.text == "" or  edtTaskFile.text == "") do return false
		
		::PATH_LIST = pp = parseCSV pathFile
		::TASK_LIST = tt = parseTask taskFile
		
		loadUniqueUsers tt pp
		
		
	)
		
	fn updateLbx = (
		ss = lbxRemoteIds.selection as array
		i = ss.count
		btnStartBatchDownload.enabled = i > 0
		lblSelectedForCnt.caption = ": (" + (i as string) + ")"
		btnStartBatchDownload.caption = "Download (" + (i as string) + ")"
	)
	
	fn loadUserSKU u p status: "rdy" = (
		lbxRemoteIds.items = #()
		::downloadIdsList = #()
		lblUserAssigneSKUCnt.caption = ": (0)"
		
		t = ::TASK_LIST
		
		ids = #()
		for i in t where i.AssignedTo == u and i.status == status do (
			append ids i.ShotId
			append ::downloadIdsList #(i.ShotId, p)
		)
		
		lbxRemoteIds.items = ids
		lblUserAssigneSKUCnt.caption = ": (" + (ids.count as string) + ")"
		
		if(ids.count > 0) do (
			try(lbxRemoteIds.selection = #{}) catch()			
			btnStartBatchDownload.enabled = true			
		)
	)
	
	fn changeProject p = (
		makeDir p all: true
		p = trimRight p @"\"
		
		isProject = doesFileExist (pathConfig.getProjectFolderPath p)
		if (not isProject) do (
			pathConfig.doProjectSetupStepsUsingDirectory p
		)
		
		pathConfig.setCurrentProjectFolder p
	)
	
	
	fn updateDownloadList = (
		v = ddlRemoteUsers.selection
		lbxRemoteIds.items = #()
		lblUserAssigneSKUCnt.caption = ": (0)"
		u = ddlRemoteUsers.items[v]
		
		if(v == 1 or v == 0 or u == "" or u[1] == "[") do (
			lblRemoteFolder.caption = "?"
			lblRemoteFolder.address = ""
			lblRemoteFolder.enabled = false
			btnStartBatchDownload.enabled = false
			return false
		)
		
		p = getUserPath ::PATH_LIST u: u		
		lblRemoteFolder.caption = p
		lblRemoteFolder.address = p
		lblRemoteFolder.enabled = true
		
		changeProject p
		
		loadUserSKU u p
		
		updateLbx()
	)
	
	fn getNumCode i = (
		n = #(0x61, 0x62, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69, 0x60)		
		s = #("1", "2", "3", "4", "5", "6", "7", "8", "9", "0")
		
		z = findItem s i
		if (z == 0) do return 0
		
		return n[z]
	)
	
	fn sendMsgToShotGunDialog sku = (
		wayfair3DUtility.Wayfair3DActions.wfShotgridShotID()
		
		WM_SETFOCUS = 0x0007
		WM_SETTEXT = 0x000C
		WM_KEYDOWN = 0x0100
		WM_KEYUP = 0x0101
		WM_PASTE = 0x0302
		WM_SETFOCUS = 0x007
		VK_TAB = 0x09
		VK_NUMPAD0 = 0x60
		VK_RETURN = 0x0D
		
		WM_SYSKEYDOWN = 0x0104
		WM_SYSKEYUP = 0x0105
		VK_CAPITAL = 0x14
		
		WM_CHAR = 0x0102
		
		hwnd = (windows.getMAXHWND())
		hwnd = (windows.getChildHWND 0 "Import Shot from ShotGrid" )[1]
		
		UIAccessor.SendMessage hwnd WM_KEYDOWN VK_TAB 0
		UIAccessor.SendMessage hwnd WM_KEYDOWN VK_TAB 0
			
		for i in 1 to sku.count do (
			ii = sku[i]
			n = getNumCode ii
			UIAccessor.SendMessage hwnd WM_KEYDOWN n 0
		)
		
		UIAccessor.PressDefaultButton()		
	)
	
	timer tmrBatchDownload "" active: false interval: 100
	
	fn getAdvancedId f = (
		if (not doesFileExist f) do return undefined
		
		if (getFileMb f > 0.20) do return undefined
		
		local a = loadFileAsArray f
		for i in a where findString i "assetid" != undefined do return parseString i "assetid\": \"" "\""
		
		return undefined
	)
	
	fn download lnk dl f1: undefined f2: undefined = (
		makeDir (getFileNamePath dl) all: true
		deleteFile dl
		
		local w = dotNetObject "System.Net.WebClient"
		try(
			local spm = dotNetClass "System.Net.ServicePointManager"
			spm.SecurityProtocol = spm.SecurityProtocol.TLS12	
			
			local h = dotnetclass "System.Net.HttpRequestHeader"
			w.Headers.set (h.cookie) (::_AUTH_.cookies)				
			w.Headers.add "Authorization" ("Bearer " + ::_AUTH_.token)
				
			local a = "?"
			if(findString lnk a != undefined) do a = "&"
			print (lnk + a + "time=" + timestamp() as string)
			
			u = dotNetObject "System.Uri" (lnk + a + "time=" + timestamp() as string)
			if (f1 != undefined and f2 != undefined) do (
				dotNet.addEventHandler w "DownloadFileCompleted" f1
				dotNet.addEventHandler w "DownloadProgressChanged" f2
			)
			w.downloadFileAsync u dl		
			w.Dispose()
		) catch (
			print (">>> " + getCurrentException())
			return false
		)
	)
	
	fn getDate = (
		d = dateTime()	
		return d.d + "." + d.m + "." + d.y
	)
	
	fn getTime = (
		d = dateTime()	
		return d.hh + ":" + d.mm + ":" + d.ss
	)
	
	fn downloadFilesAsync = (
		::isNowDownloading = true
		_rStepBatchDownloads.btnStartBatchDownload.enabled = false
			
		if(::qeueDownloadList == undefined or ::qeueDownloadList.count == 0 or qeueDownloadList[1] == undefined) do (
			::isNowDownloading = false
			
			return false
		)
		
		local q = ::qeueDownloadList[1]
		
		::_AUTH_ = postAuth()
			
		if (::_AUTH_ == undefined) do (
			print ">>> Can't authorize to WayFair Partners site!"
			messageBox "Problem with authorization to WayFair Partners site.\nPlease try again!" title: "Error!"
			return false
		)
			
		local id = q[1]
		local p = q[2]		
		local g = postGraphql id
		
		if (g == undefined) do (
			print ">>> Can't retrive GraphQL data!"
			return false
		)
		
		::qeueDownloadList[1][3] = g
		
		f = getDownloadFolder p id
		
		makeDir f all: true
			
		putDownloadIni f "date_start" (getDate())
		putDownloadIni f "time_start" (getTime())
		putDownloadIni f "shot_id" id
		putDownloadIni f "template_id" g.template_id
		putDownloadIni f "model_id" g.model_id
		putDownloadIni f "mpid" g.mpid
		putDownloadIni f "path" f
			
		-- Download new file from json assetid param
		fn onModelDownloadCompleted s a = (
			local n = readFileName s			
			local q = ::qeueDownloadList[1]
			local id = q[1]
			local p = q[2]
			local g = q[3]
			local f = getDownloadFolder p id
			local u = formatString ::urlDownlodZip v: #(g.model_id)		
			local dl = f + "model.zip"
			
			putDownloadIni f "model" n
			
			aid = getAdvancedId dl			
			if (aid != undefined) do (
				putDownloadIni f "aid" aid
				
				local u = formatString ::urlDownlodZip v: #(aid)
				
				download u dl
			)
		)
		
		fn onModelProgress s a = (
		)
		
		local u = formatString ::urlDownlodZip v: #(g.model_id)		
		local dl = f + "model.zip" 
		download u dl f1: onModelDownloadCompleted f2: onModelProgress
		
		fn onStudioDownloadProcess s a = (
			local p = a.ProgressPercentage
			::isNowDownloading = true
			
			if (::prevProgress != p) do (
				try(
					_rStepBatchDownloads.pbDownload.value = p
					boost()
				) catch()
			)
			
			if(::cancelDownload) do s.CancelAsync()	
		)
			
		fn onStudioDownloadComplete s a = (
			local n = readFileName s
			local q = ::qeueDownloadList[1]
			local id = q[1]
			local p = q[2]
			local g = q[3]
			local f = getDownloadFolder p id
			
			putDownloadIni f "studio" n
			putDownloadIni f "date_end" (getDate())
			putDownloadIni f "time_end" (getTime())
			
			::completedDownloads += 1
				
			if(::qeueDownloadList.count != 0) do deleteItem ::qeueDownloadList 1			
			if(::qeueDownloadList.count != 0) do _rStepBatchDownloads.tmrBatchDownload.active = true
			if(::qeueDownloadList.count == 0) do _rStepBatchDownloads.btnStartBatchDownload.enabled = true
			
			boost()
		)
		
		local u = formatString ::urlDownlodZip v: #(g.template_id)
		local dl = f + "studio.zip"
		download u dl f1: onStudioDownloadComplete f2: onStudioDownloadProcess
	)
	
	on tmrBatchDownload tick do (
		tmrBatchDownload.active = false
		
		::cancelDownload = false
		::completedDownloads = 0
			
		/*try(syncWorker2.CancelAsync()) catch()
		try(syncWorker2.Dispose()) catch()
		try(dotNet.removeEventHandler syncWorker2 "DoWork" downloadFilesAsync) catch()
		
		syncWorker2 = dotnetobject "CSharpUtilities.SynchronizingBackgroundWorker"
		syncWorker2.WorkerSupportsCancellation = true 
		syncWorker2.CancelAsync()
		dotNet.addEventHandler syncWorker2 "DoWork" downloadFilesAsync
		try(syncWorker2.RunWorkerAsync()) catch()*/
			
		downloadFilesAsync()
	)
	
	-- !! Run download function
	fn startDownload = (
		uid = ddlRemoteUsers.selection
		u = ddlRemoteUsers.items[uid]		
		p = getUserPath ::PATH_LIST u: u
			
		tmrBatchDownload.active = true			
	)
		
	on btnSearchTaskFile pressed do (
		f = getOpenFileName types:"Excel (*.csv)|*.csv"
		if (f == undefined) do return false		
		if (findString (getFilenameFile f) "task" == undefined) do return messageBox "Please select \"Task.csv\" file!" title: "Error!"
		
		'*'.add "TASK_FILE" f
		
		loadSettings()
	)
	
	on btnSearchPathsFile pressed do (
		f = getOpenFileName types:"Excel (*.csv)|*.csv"
		if (f == undefined) do return false		
		if (findString (getFilenameFile f) "path" == undefined) do return messageBox "Please select \"PathName.csv\" file!" title: "Error!"
		
		'*'.add "PATH_FILE" f
		
		loadSettings()
	)
	
	on btnStartBatchDownload pressed do (
		taskFile = edtTaskFile.text
		pathFile = edtPathsFile.text
		
		if (taskFile == "" or pathFile == "") do return messageBox "Please select all \"Parse Files\"!" title: "Error!"
	)
	
	on tmrLoad tick do (
		tmrLoad.active = false
		
		loadSettings()
	)
	
	on _rStepBatchDownloads open do (
		tmrLoad.active = true
		
		/*global syncWorker2 = dotnetobject "CSharpUtilities.SynchronizingBackgroundWorker"*/
		
		::completedDownloads = 0
	)
	
	on ddlRemoteUsers selected v do (		
		updateDownloadList()
	)
	
	on lbxRemoteIds selectionEnd do (
		updateLbx()
	)
	
	on btnDeselectAll pressed do (
		lbxRemoteIds.selection = #{}
		updateLbx()
	)
	
	on btnSelectAll pressed do (		
		lbxRemoteIds.selection = for i in 1 to lbxRemoteIds.items.count collect i
		updateLbx()
	)
	
	
	on btnStartBatchDownload pressed do (		
		uid = ddlRemoteUsers.selection
		u = ddlRemoteUsers.items[uid]
		
		if(uid == 0 or uid == 1) do (
			messageBox "Please select user from list!" title: "Error!"
			return false
		)
		
		if (u == "[") do (
			messageBox "This user with error!" title: "Error!"
			return false
		)
		
		if (wayfair3DUtility == undefined) do (
			messageBox "Please install WayFair Plugin first!" title: "Error!"
			return false
		)
		
		lbxSel = lbxRemoteIds.selection as array
		if (lbxSel.count == 0) do (
			messageBox "Please select items from list!" title: "Error!"
			return false 
		)
		
		::qeueDownloadList = #()
		for i in lbxSel do (
			append ::qeueDownloadList (deepCopy ::downloadIdsList[i])
		)
		
		startDownload()
	)
	
	on _rStepBatchDownloads close do (
		--syncWorker2.CancelAsync()
	)
	
	on _rStepBatchDownloads rolledUp x do sliderStep 1 x
)

rollout _rSettings "Settings" (
	group "Dock Script" (
		checkbox cbxDockable "Dock To Side" 
		radioButtons rdoDockTo "" labels:#("Left", "Right") default:1 columns:2 align: #left		
	)
	
	fn fnSetDock d s = (
		'*'.add "DOCKABLE" d
		'*'.add "DOCKSIDE" s
			
		if(d) then (
			cui.RegisterDialogBar floaterShotGunTools style:#(#cui_floatable, #cui_dock_vert, #cui_handles, #cui_max_sized, #style_toolwindow, #style_sysmenu)
		
			case s of (
				1:  cui.DockDialogBar floaterShotGunTools #cui_dock_left
				2:  cui.DockDialogBar floaterShotGunTools #cui_dock_right
			)			
		)
		else (
			if(floaterShotGunTools.dialogBar) do (
				cui.UnRegisterDialogBar floaterShotGunTools	
			)
			
			if (not floaterShotGunTools.dialogBar) do (
				x = '*'.get "x" type: #int
				y = '*'.get "y" type: #int
				
				floaterShotGunTools.pos = [x, y]
			)								
		)			
	)
	
	on _rSettings close do (
		p = floaterShotGunTools.pos
		
		'*'.add "x" p[1]
		'*'.add "y" p[2]
	)
	
	on cbxDockable changed x do (
		s = rdoDockTo.state
		fnSetDock x s
	)
	
	on rdoDockTo changed s do (
		x = cbxDockable.checked		
		if(x == true) do fnSetDock x s
	)
	
	on _rSettings open do (
		x = '*'.get "x" type: #int
		y = '*'.get "y" type: #int
		
		floaterShotGunTools.pos = [x, y]
		
		d = '*'.get "DOCKABLE" type: #bool
		s = '*'.get "DOCKSIDE" type: #int
		
		fnSetDock d s
		
		try (cbxDockable.checked = d) catch()
		try (rdoDockTo.state = s) catch(rdoDockTo.state = 1)
	)
	
	
	on _rSettings rolledUp x do sliderStep 2 x
)

rollout _rAboutSGT "About" (
    label lblName "" 
    label lblVer "" 
    
    label lblAuthor "" height: 30
    hyperlink lblCopy ""  align: #center
    
    fn getScriptInfo s releaseInfo: "" =  (
        if(releaseInfo != "") do (
            r = getINISetting s releaseInfo
            return r
        )

        v = getINISetting s "INFO" "VERSION"
        a = getINISetting s "INFO" "AUTHOR"
        n = getINISetting s "INFO" "NAME"
        o = getINISetting s "ABOUT"
        c = getINISetting s "INFO" "DEV"
        h = getINISetting s "INFO" "HELP"
        
        r = for i in (getINISetting s) where (i != "ABOUT" and i != "SCRIPT" and i != "COPY") collect i
        
        return #(n, a, v, o, r, c, h)
    )

    on _rAboutSGT open do (
        i = getScriptInfo (getThisScriptFilename())
   
        lblName.caption = i[1]
        lblAuthor.caption = i[2]
        lblVer.caption = i[3]
        lblCopy.address  = lblCopy.caption = i[6]
			
		try (floaterShotGunTools.title = i[1] + " " +  i[3]) catch()
    )
	
	on _rAboutSB rolledUp x do sliderStep 3 x
)

addRollout _rStepBatchDownloads floaterShotGunTools rolledUp: false
addRollout _rSettings floaterShotGunTools rolledUp: true
addRollout _rAboutSGT floaterShotGunTools rolledUp: true 