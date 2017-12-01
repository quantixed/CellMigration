#pragma rtGlobals=3		// Use modern global access method and strict wave access.
#pragma version=1.04		// version number of Migrate()
#include <Waves Average>

// LoadMigration contains 3 procedures to analyse cell migration in IgorPro
// Use ImageJ to track the cells. Outputs from tracking are saved in sheets in an Excel Workbook, 1 per condition
// Execute Migrate().
// This function will trigger the load and the analysis of cell migration via two functions
// LoadMigration() - will load all sheets of migration data from a specified excel file
// MakeTracks() - does the analysis
// NOTE no headers in Excel file. Keep data to columns A-H, max of 2000 rows
// columns are
// A - 0 - ImageJ row
// B - 1 - Track No
// C - 2 - Slice No
// D - 3 - x (in px)
// E - 4 - y (in px)
// F - 5 - distance
// G - 6 - speed
// H - 7 - pixel value

// Menu item for easy execution
Menu "Macros"
	"Cell Migration...",  SetUpMigration()
End

Function SetUpMigration()
	SetDataFolder root:
	// kill all windows and waves before we start
	CleanSlate()
	
	Variable cond = 2
	Variable tStep = 20
	Variable pxSize = 0.32
	
	Prompt cond, "How many conditions?"
	Prompt tStep, "Time interval (min)"
	Prompt  pxSize, "Pixel size (µm)"
	DoPrompt "Specify", cond, tStep, pxSize
	
	Make/O/N=3 paramWave={cond,tStep,pxSize}
	myIO_Panel(cond)
End

// Loads the data and performs migration analysis
Function Migrate()
	WAVE/Z paramWave
	if(!WaveExists(paramWave))
		Abort "Setup has failed. Missing paramWave."
	endif
	
	Variable cond = paramWave[0]
	Variable tStep = paramWave[1]
	Variable pxSize = paramWave[2]
	
	// Pick colours from SRON palettes
	String pal
	if(cond == 1)
		pal = SRON_1
	elseif(cond == 2)
		pal = SRON_2
	elseif(cond == 3)
		pal = SRON_3
	elseif(cond == 4)
		pal = SRON_4
	elseif(cond == 5)
		pal = SRON_5
	elseif(cond == 6)
		pal = SRON_6
	elseif(cond == 7)
		pal = SRON_7
	elseif(cond == 8)
		pal = SRON_8
	elseif(cond == 9)
		pal = SRON_9
	elseif(cond == 10)
		pal = SRON_10
	elseif(cond == 11)
		pal = SRON_11
	else
		pal = SRON_12
	endif

	Make/O/N=(cond,3) colorwave
	Make/O/T/N=(cond) sum_Label
	Make/O/N=(cond) sum_MeanSpeed, sum_SemSpeed, sum_NSpeed
	Make/O/N=(cond) sum_MeanIV, sum_SemIV
	
	String pref, lab
	Variable color
	Variable/G gR, gG, gB
	
	String fullList = "cdPlot;ivPlot;ivHPlot;dDPlot;MSDPlot;DAPlot;"
	String name
	Variable i
	
	for(i = 0; i < 6; i += 1)
		name = StringFromList(i, fullList)
		KillWindow/Z $name
		Display/N=$name/HIDE=1		
	endfor
	
	String dataFolderName = "root:data"
	NewDataFolder/O $dataFolderName // make root:data: but don't put anything in it yet
	
	WAVE/T condWave = root:condWave
	
	for(i = 0; i < cond; i += 1)
		pref = condWave[i]
		
		// add underscore if user forgets
		if(StringMatch(pref,"*_") == 0)
			pref = pref + "_"
		endif
		
		lab = ReplaceString("_",pref,"")
		sum_Label[i] = lab
		
		// specify colours
		if(cond < 12)
			color = str2num(StringFromList(i,pal))
			gR = hexcolor_red(color)
			gG = hexcolor_green(color)
			gB = hexcolor_blue(color)
		else
			color = str2num(StringFromList(round((i)/12),pal))
			gR = hexcolor_red(color)
			gG = hexcolor_green(color)
			gB = hexcolor_blue(color)
		endif
		colorwave[i][0] = gR
		colorwave[i][1] = gG
		colorwave[i][2] = gB
		// make data folder
		dataFolderName = "root:data:" + RemoveEnding(pref)
		NewDataFolder/O/S $dataFolderName
		// run other procedures
		LoadMigration(pref,i)
		MakeTracks(pref,tStep,pxSize)
		SetDataFolder root:
	endfor
	
	KillWindow/Z summaryLayout
	NewLayout/N=summaryLayout
	
	// Tidy up summary windows
	SetAxis/W=cdPlot/A/N=1 left
	Label/W=cdPlot left "Cumulative distance (µm)"
	Label/W=cdPlot bottom "Time (min)"
		AppendLayoutObject /W=summaryLayout graph cdPlot
	SetAxis/W=ivPlot/A/N=1 left
	Label/W=ivPlot left "Instantaneous Speed (µm/min)"
	Label/W=ivPlot bottom "Time (min)"
		AppendLayoutObject /W=summaryLayout graph ivPlot
	SetAxis/W=ivHPlot/A/N=1 left
	SetAxis/W=ivHPlot bottom 0,2
	Label/W=ivHPlot left "Frequency"
	Label/W=ivHPlot bottom "Instantaneous Speed (µm/min)"
	ModifyGraph/W=ivHPlot mode=6
		AppendLayoutObject /W=summaryLayout graph ivHPlot
	Label/W=dDPlot left "Directionality ratio (d/D)"
	Label/W=dDPlot bottom "Time (min)"
		AppendLayoutObject /W=summaryLayout graph dDPlot
	ModifyGraph/W=MSDPlot log=1
	SetAxis/W=MSDPlot/A/N=1 left
	Wave w = WaveRefIndexed("MSDPlot",0,1)
	SetAxis/W=MSDPlot bottom tStep,((numpnts(w) * tStep)/2)
	Label/W=MSDPlot left "MSD"
	Label/W=MSDPlot bottom "Time (min)"
		AppendLayoutObject /W=summaryLayout graph MSDPlot
	SetAxis/W=DAPlot left 0,1
	Wave w = WaveRefIndexed("DAPlot",0,1)
	SetAxis/W=DAPlot bottom 0,((numpnts(w)*tStep)/2)
	Label/W=DAPlot left "Direction autocorrelation"
	Label/W=DAPlot bottom "Time (min)"
		AppendLayoutObject /W=summaryLayout graph DAPlot
	
	// average the speed data from all conditions	
	String wList, newName, wName
	Variable nTracks, last, j
	
	for(i = 0; i < cond; i += 1)
		pref = sum_Label[i] + "_"
		dataFolderName = "root:data:" + RemoveEnding(pref)
		SetDataFolder $dataFolderName
		wList = WaveList("cd_" + pref + "*", ";","")
		nTracks = ItemsInList(wList)
		newName = "sum_Speed_" + RemoveEnding(pref)
		Make/O/N=(nTracks) $newName
		WAVE w0 = $newName
		for(j = 0; j < nTracks; j += 1)
			wName = StringFromList(j,wList)
			Wave w1 = $wName
			last = numpnts(w1) - 1	// finds last row (max cumulative distance)
			w0[j] = w1[last]/(last*tStep)	// calculates speed
		endfor
		WaveStats/Q w0
		sum_MeanSpeed[i] = V_avg
		sum_SemSpeed[i] = V_sem
		sum_NSpeed[i] = V_npnts
	endfor
	KillWindow/Z SpeedTable
	Edit/N=SpeedTable/HIDE=1 sum_Label,sum_MeanSpeed,sum_MeanSpeed,sum_SemSpeed,sum_NSpeed
	KillWindow/Z SpeedPlot
	Display/N=SpeedPlot/HIDE=1 sum_MeanSpeed vs sum_Label
	Label/W=SpeedPlot left "Speed (µm/min)"
	SetAxis/W=SpeedPlot/A/N=1/E=1 left
	ErrorBars/W=SpeedPlot sum_MeanSpeed Y,wave=(sum_SemSpeed,sum_SemSpeed)
	ModifyGraph/W=SpeedPlot zColor(sum_MeanSpeed)={colorwave,*,*,directRGB,0}
	ModifyGraph/W=SpeedPlot hbFill=2
	AppendToGraph/R/W=SpeedPlot sum_MeanSpeed vs sum_Label
	SetAxis/W=SpeedPlot/A/N=1/E=1 right
	ModifyGraph/W=SpeedPlot hbFill(sum_MeanSpeed#1)=0,rgb(sum_MeanSpeed#1)=(0,0,0)
	ModifyGraph/W=SpeedPlot noLabel(right)=2,axThick(right)=0,standoff(right)=0
	ErrorBars/W=SpeedPlot sum_MeanSpeed#1 Y,wave=(sum_SemSpeed,sum_SemSpeed)
		AppendLayoutObject /W=summaryLayout graph SpeedPlot
	
	// average instantaneous speed variances
	for(i = 0; i < cond; i += 1) // loop through conditions, 0-based
		pref = sum_Label[i] + "_"
		dataFolderName = "root:data:" + RemoveEnding(pref)
		SetDataFolder $dataFolderName
		wList = WaveList("iv_" + pref + "*", ";","")
		nTracks = ItemsInList(wList)
		newName = "sum_ivVar_" + ReplaceString("_",pref,"")
		Make/O/N=(nTracks) $newName
		WAVE w0 = $newName
		for(j = 0; j < nTracks; j += 1)
			wName = StringFromList(j,wList)
			Wave w1 = $wName
			w0[j] = variance(w1)	// calculate varance for each cell
		endfor
		WaveStats/Q w0
		sum_MeanIV[i] = V_avg
		sum_SemIV[i] = V_sem
	endfor
	AppendToTable/W=SpeedTable sum_MeanIV,sum_SemIV
	KillWindow/Z IVCatPlot
	Display/N=IVCatPlot/HIDE=1 sum_MeanIV vs sum_Label
	Label/W=IVCatPlot left "Variance (µm/min)"
	SetAxis/W=IVCatPlot/A/N=1/E=1 left
	ErrorBars/W=IVCatPlot sum_MeanIV Y,wave=(sum_SemIV,sum_SemIV)
	ModifyGraph/W=IVCatPlot zColor(sum_MeanIV)={colorwave,*,*,directRGB,0}
	ModifyGraph/W=IVCatPlot hbFill=2
	AppendToGraph/R/W=IVCatPlot sum_MeanIV vs sum_Label
	SetAxis/W=IVCatPlot/A/N=1/E=1 right
	ModifyGraph/W=IVCatPlot hbFill(sum_MeanIV#1)=0,rgb(sum_MeanIV#1)=(0,0,0)
	ModifyGraph/W=IVCatPlot noLabel(right)=2,axThick(right)=0,standoff(right)=0
	ErrorBars/W=IVCatPlot sum_MeanIV#1 Y,wave=(sum_SemIV,sum_SemIV)
		AppendLayoutObject /W=summaryLayout graph IVCatPlot
	
	SetDataFolder root:
	
	// Tidy summary layout
	DoWindow/F summaryLayout
	// in case these are not captured as prefs
	LayoutPageAction size(-1)=(595, 842), margins(-1)=(18, 18, 18, 18)
	ModifyLayout units=0
	ModifyLayout frame=0,trans=1
	Execute /Q "Tile"

	// when we get to the end, print (pragma) version number
	Print "*** Executed Migrate v", GetProcedureVersion("CellMigration.ipf")
	KillWindow/Z FilePicker
End

// This function will load the tracking data from an Excel Workbook
/// @param pref	prefix for excel workbook e.g. "ctrl_"
Function LoadMigration(pref,ii)
	String pref
	Variable ii
	
	WAVE/T PathWave1 = root:PathWave1
	String sheet, prefix, wList
	Variable i
	
	// opens a dialog to specify xls file. Reads sheets and then loads each.
	XLLoadWave/J=1 PathWave1[ii]
	Variable moviemax = ItemsInList(S_value)
//	NewPath/O/Q path1, S_path
	
	for(i = 0; i < moviemax; i += 1)
		sheet = StringFromList(i,S_Value)
		prefix = pref + num2str(i)
		XLLoadWave/S=sheet/R=(A1,H2000)/O/K=0/N=$prefix PathWave1[ii]
		wList = wavelist(prefix + "*",";","")	// make matrix for each sheet
		Concatenate/O/KILL wList, $prefix
	endfor
	
	Print "*** Condition", RemoveEnding(pref), "was loaded from", S_path
	
End

// This function will make cumulative distance waves for each cell. They are called cd_*
/// @param pref	prefix for excel workbook e.g. "ctrl_"
/// @param tStep	timestep. Interval/frame rate of movie.
/// @param pxSize	pixel size. xy scaling.
Function MakeTracks(pref,tStep,pxSize)
	String pref
	Variable tStep, pxSize
	
	NVAR cR = root:gR
	NVAR cG = root:gG
	NVAR cB = root:gB
	
	String wList0 = WaveList(pref + "*",";","") // find all matrices

	Variable nWaves = ItemsInList(wList0)
	
	Variable nTrack
	String mName0, newName, plotName, avList, avName, errName
	Variable i, j
	
	String layoutName = pref + "layout"
	KillWindow/Z $layoutName		// Kill the layout if it exists
	NewLayout/N=$layoutName		// Igor 7 has multipage layouts, using separate layouts for now.

	// cumulative distance and plot over time	
	plotName = pref + "cdplot"
	KillWindow/Z $plotName	// set up plot
	Display/N=$plotName/HIDE=1

	for(i = 0; i < nWaves; i += 1)
		mName0 = StringFromList(i,wList0)
		WAVE m0 = $mName0
		Duplicate/O/RMD=[][5,5] m0, tDistW	// distance
		Duplicate/O/RMD=[][1,1] m0, tCellW	// cell number
		Redimension/N=-1 tDistW, tCellW // make 1D
		nTrack = WaveMax(tCellW)	// find maximum track number
		for(j = 1; j < (nTrack+1); j += 1)	// index is 1-based
			newName = "cd_" + mName0 + "_" + num2str(j)
			Duplicate/O tDistW $newName
			WAVE w2 = $newName
			w2 = (tCellW[p] == j) ? tDistW[p] : NaN
			WaveTransform zapnans w2
			if(numpnts(w2) == 0)
				KillWaves/Z w2	// get rid of any tracks that didn't exist
			else
				w2[0] = 0	// first point in distance trace is -1 so correct this
				Integrate/METH=0 w2	// make cumulative distance
				SetScale/P x 0,tStep,"min", w2
				AppendtoGraph/W=$plotName $newName
			endif
		endfor
	endfor
	ModifyGraph/W=$plotName rgb=(cR,cG,cB)
	avList = Wavelist("cd*",";","WIN:"+ plotName)
	avName = "W_Ave_cd_" + ReplaceString("_",pref,"")
	errName = ReplaceString("Ave", avName, "Err")
	fWaveAverage(avList, "", 3, 1, AvName, ErrName)
	AppendToGraph/W=$plotName $avName
	Label/W=$plotName left "Cumulative distance (µm)"
	ErrorBars/W=$plotName $avName Y,wave=($ErrName,$ErrName)
	ModifyGraph/W=$plotName lsize($avName)=2,rgb($avName)=(0,0,0)
	
	AppendLayoutObject/W=$layoutName graph $plotName
	
	// instantaneous speed over time	
	plotName = pref + "ivplot"
	KillWindow/Z $plotName	// set up plot
	Display/N=$plotName/HIDE=1

	for(i = 0; i < nWaves; i += 1)
		mName0 = StringFromList(i,wList0)
		WAVE m0 = $mName0
		Duplicate/O/RMD=[][5,5] m0, tDistW	// distance
		Duplicate/O/RMD=[][1,1] m0, tCellW	// cell number
		Redimension/N=-1 tDistW, tCellW // make 1D
		nTrack = WaveMax(tCellW)	// find maximum track number
		for(j = 1; j < (nTrack+1); j += 1)	// index is 1-based
			newName = "iv_" + mName0 + "_" + num2str(j)
			Duplicate/O tDistW $newName
			WAVE w2 = $newName
			w2 = (tCellW[p] == j) ? tDistW[p] : NaN
			WaveTransform zapnans w2
			if(numpnts(w2) == 0)
				KillWaves w2
			else
				w2[0] = 0	// first point in distance trace is -1, so correct this
				w2 /= tStep	// make instantaneous speed (units are µm/min)
				SetScale/P x 0,tStep,"min", w2
				AppendtoGraph/W=$plotName $newName
			endif
		endfor
	endfor
	ModifyGraph/W=$plotName rgb=(cR,cG,cB)
	avList = Wavelist("iv*",";","WIN:"+ plotName)
	avName = "W_Ave_iv_" + ReplaceString("_",pref,"")
	errName = ReplaceString("Ave", avName, "Err")
	fWaveAverage(avList, "", 3, 1, AvName, ErrName)
	AppendToGraph/W=$plotName $avName
	Label/W=$plotName left "Instantaneous Speed (µm/min)"
	ErrorBars/W=$plotName $avName Y,wave=($ErrName,$ErrName)
	ModifyGraph/W=$plotName lsize($avName)=2,rgb($avName)=(0,0,0)
	
	AppendLayoutObject/W=$layoutName graph $plotName
	
	plotName = pref + "ivHist"
	KillWindow/Z $plotName	//set up plot
	Display/N=$plotName/HIDE=1
	
	Concatenate/O/NP avList, tempwave
	newName = pref + "ivHist"	// note that this makes a name like Ctrl_ivHist
	Variable bval=ceil(wavemax(tempwave)/(sqrt((3*pxsize)^2)/tStep))
	Make/O/N=(bval) $newName
	Histogram/P/B={0,(sqrt((3*pxsize)^2)/tStep),bVal} tempwave,$newName
	AppendToGraph/W=$plotName $newName
	ModifyGraph/W=$plotName rgb=(cR,cG,cB)
	ModifyGraph/W=$plotName mode=5,hbFill=4
	SetAxis/W=$plotName/A/N=1/E=1 left
	SetAxis/W=$plotName bottom 0,2
	Label/W=$plotName left "Frequency"
	Label/W=$plotName bottom "Instantaneous Speed (µm/min)"
	KillWaves/Z tempwave
	
	AppendLayoutObject/W=$layoutName graph $plotName
	
	// plot out tracks
	plotName = pref + "tkplot"
	KillWindow/Z $plotName	//set up plot
	Display/N=$plotName/HIDE=1
	
	Variable off
	
	for(i = 0; i < nWaves; i += 1)
		mName0 = StringFromList(i,wList0)
		WAVE m0 = $mName0
		Duplicate/O/RMD=[][3,3] m0, tXW	//x pos
		Duplicate/O/RMD=[][4,4] m0, tYW	//y pos
		Duplicate/O/RMD=[][1,1] m0, tCellW	//track number
		Redimension/N=-1 tXW,tYW,tCellW		
		nTrack=WaveMax(tCellW)	//find maximum track no.
		for(j = 1; j < (nTrack+1); j += 1)	//index is 1-based
			newName = "tk_" + mName0 + "_" + num2str(j)
			Duplicate/O tXW w3	// tried to keep wn as references, but these are very local
			w3 = (tCellW[p] == j) ? w3[p] : NaN
			WaveTransform zapnans w3
			if(numpnts(w3) == 0)
				Killwaves w3
			else
				off = w3[0]
				w3 -= off	//set to origin
				w3 *= pxSize
				// do the y wave
				Duplicate/O tYW w4
				w4 = (tCellW[p] == j) ? w4[p] : NaN
				WaveTransform zapnans w4
				off = w4[0]
				w4 -= off
				w4 *= pxSize
				Concatenate/O/KILL {w3,w4}, $newName
				WAVE w5 = $newName
				AppendtoGraph/W=$plotName w5[][1] vs w5[][0]
			endif
		endfor
		Killwaves/Z tXW,tYW,tCellW //tidy up
	endfor
	ModifyGraph/W=$plotName rgb=(cR,cG,cB)
	SetAxis/W=$plotName left -250,250;DelayUpdate
	SetAxis/W=$plotName bottom -250,250;DelayUpdate
	ModifyGraph/W=$plotName width={Plan,1,bottom,left};DelayUpdate
	ModifyGraph/W=$plotName mirror=1;DelayUpdate
	ModifyGraph/W=$plotName grid=1
	
	AppendLayoutObject/W=$layoutName graph $plotName
	
	// calculate d/D directionality ratio
	plotName = pref + "dDplot"
	KillWindow/Z $plotName	// setup plot
	Display/N=$plotName/HIDE=1
	
	String wName0, wName1
	Variable len
	wList0 = WaveList("tk_" + pref + "*", ";","")
	nWaves = ItemsInList(wList0)
	
	for(i = 0; i < nWaves; i += 1)
		wName0 = StringFromList(i,wList0)			// tk wave
		wName1 = ReplaceString("tk",wName0,"cd")	// cd wave
		WAVE w0 = $wName0
		WAVE w1 = $wName1
		newName = ReplaceString("tk",wName0,"dD")
		Duplicate/O w1 $newName
		WAVE w2 = $newName
		len = numpnts(w2)
		w2[] = (w1[p] == 0) ? 1 : sqrt(w0[p][0]^2 + w0[p][1]^2) / w1[p]
		w2[0] = NaN	// d/D at point 0 is not a number
//		for(j = 1; j < len; j += 1)
//			if(w1[j] == 0)
//				w2[j] = 1
//			else
//				w2[j] = sqrt(w0[j][0]^2 + w0[j][1]^2) / w1[j]
//			endif
//		endfor
		AppendtoGraph/W=$plotName w2
	Endfor
	ModifyGraph/W=$plotName rgb=(cR,cG,cB)
	avList = Wavelist("dD*",";","WIN:"+ plotName)
	avName = "W_Ave_dD_" + ReplaceString("_",pref,"")
	errName = ReplaceString("Ave", avName, "Err")
	fWaveAverage(avList, "", 3, 1, AvName, ErrName)
	AppendToGraph/W=$plotName $avName
	Label/W=$plotName left "Directionality ratio (d/D)"
	Label/W=$plotName bottom "Time (min)"
	ErrorBars/W=$plotName $avName Y,wave=($ErrName,$ErrName)
	ModifyGraph/W=$plotName lsize($avName)=2,rgb($avName)=(0,0,0)
	
	AppendLayoutObject/W=$layoutName graph $plotName
	
	// calculate MSD (overlapping method)
	plotName = pref + "MSDplot"
	KillWindow/Z $plotName	//setup plot
	Display/N=$plotName/HIDE=1
	
	wList0 = WaveList("tk_" + pref + "*", ";","")
	nWaves = ItemsInList(wList0)
	Variable k
	
	for(i = 0; i < nWaves; i += 1)
		wName0 = StringFromList(i,wList0)	// tk wave
		WAVE w0 = $wName0
		len = DimSize(w0,0)
		mName0 = ReplaceString("tk",wName0,"MSDtemp")
		newName = ReplaceString("tk",wName0,"MSD")	// for results of MSD per cell
		Make/O/N=(len,len-1) $mName0=NaN // this calculates all, probably only need first half
		WAVE m0 = $mName0
		for(k = 0; k < len-1; k += 1)	// by col, this is delta T
			for(j = 1; j < len; j += 1)	// by row, this is the starting frame
				if(j > k)
					m0[j][k]= ((w0[j][0] - w0[j-(k+1)][0])^2)+((w0[j][1] - w0[j-(k+1)][1])^2)
				endif
			endfor
		endfor
		Make/O/N=(len) $newName=NaN
		WAVE w2 = $newName
		// extract cell MSDs per time point
		for(k = 0; k < (len-1); k += 1)
			Duplicate/FREE/O/R=[][k] m0, w1 //no need to redimension or zapnans
			Wavestats/Q w1			
			w2[k+1] = v_avg
		endfor
		KillWaves m0
		SetScale/P x 0,tStep,"min", w2
		AppendtoGraph/W=$plotName w2
	endfor
	ModifyGraph/W=$plotName rgb=(cR,cG,cB)
	avList = Wavelist("MSD*",";","WIN:"+ plotName)
	avName = "W_Ave_MSD_" + ReplaceString("_",pref,"")
	errName = ReplaceString("Ave", avName, "Err")
	fWaveAverage(avList, "", 3, 1, avName, errName)
	AppendToGraph/W=$plotName $avName
	ModifyGraph/W=$plotName log=1
	SetAxis/W=$plotName/A/N=1 left
	len = numpnts($avName)*tStep
	SetAxis/W=$plotName bottom tStep,(len/2)
	Label/W=$plotName left "MSD"
	Label/W=$plotName bottom "Time (min)"
	ErrorBars/W=$plotName $avName Y,wave=($errName,$errName)
	ModifyGraph/W=$plotName lsize($avName)=2,rgb($avName)=(0,0,0)
	
	AppendLayoutObject /W=$layoutName graph $plotName
	
	// calculate direction autocorrelation
	plotName = pref + "DAplot"
	KillWindow/Z $plotName	// setup plot
	Display/N=$plotName/HIDE=1
	
	for(i = 0; i < nWaves; i += 1)
		wName0 = StringFromList(i,wList0)			// tk wave
		WAVE w0 = $wName0
		len = DimSize(w0,0)	// len is number of frames
		Make/O/N=(len-1,2) vwave	// make vector wave. nVectors is len-1
		vwave = w0[p+1][q] - w0[p][q]
		Make/O/D/N=(len-1) magwave	// make magnitude wave. nMagnitudes is len-1
		magwave = sqrt((vwave[p][0]^2) + (vwave[p][1]^2))
		vwave /= magwave[p]	// normalise the vectors
		mName0 = ReplaceString("tk",wName0,"DAtemp")
		newName = ReplaceString("tk",wName0,"DA")	// for results of DA per cell
		Make/O/N=(len-1,len-2) $mName0 = NaN	// matrix for results (nVectors,nÆt)
		WAVE m0 = $mName0
		for(k = 0; k < len-1; k += 1)	// by col, this is Æt 0-based
			for(j = 0; j < len; j += 1)	// by row, this is the starting vector 0-based
				if((j+(k+1)) < len-1)
					m0[j][k]= (vwave[j][0] * vwave[j+(k+1)][0]) + (vwave[j][1] * vwave[j+(k+1)][1])
				endif
			endfor
		endfor
		Make/O/N=(len-1) $newName = NaN // npnts is len-1 not len-2 because of 1st point = 1
		Wave w2 = $newName
		w2[0] = 1
		// extract cell average cos(theta) per time interval
		for(k = 0; k < len-2; k += 1)
			Duplicate/FREE/O/RMD=[][k,k] m0, w1 //no need to redimension or zapnans
			Wavestats/Q w1	//mean function requires zapnans	
			w2[k+1] = v_avg
		endfor
		KillWaves m0
		SetScale/P x 0,tStep,"min", w2
		AppendtoGraph/W=$plotName w2
	endfor
	Killwaves/Z vwave,magwave
	ModifyGraph/W=$plotName rgb=(cR,cG,cB)
	avList = Wavelist("DA*",";","WIN:"+ plotName)
	avName = "W_Ave_DA_" + ReplaceString("_",pref,"")
	errName = ReplaceString("Ave", avName, "Err")
	fWaveAverage(avList, "", 3, 1, avName, errName)
	AppendToGraph/W=$plotName $avName
	SetAxis/W=$plotName left -1,1
	Label/W=$plotName left "Direction autocorrelation"
	Label/W=$plotName bottom "Time (min)"
	ErrorBars/W=$plotName $avName Y,wave=($errName,$errName)
	ModifyGraph/W=$plotName lsize($avName)=2,rgb($avName)=(0,0,0)
	
	AppendLayoutObject/W=$layoutName graph $plotName
	
	// Plot these summary windows at the end
	avName = "W_Ave_cd_" + ReplaceString("_",pref,"")
	errName = ReplaceString("Ave", avName, "Err")
	AppendToGraph/W=cdPlot $avName
	ErrorBars/W=cdPlot $avName Y,wave=($errName,$errName)
	ModifyGraph/W=cdPlot lsize($avName)=2,rgb($avName)=(cR,cG,cB)
	
	avName = "W_Ave_iv_" + ReplaceString("_",pref,"")
	errName = ReplaceString("Ave", avName, "Err")
	AppendToGraph/W=ivPlot $avName
	ErrorBars/W=ivPlot $avName Y,wave=($errName,$errName)
	ModifyGraph/W=ivPlot lsize($avName)=2,rgb($avName)=(cR,cG,cB)
	
	newName = pref + "ivHist"
	AppendToGraph/W=ivHPlot $newName
	ModifyGraph/W=ivHPlot rgb($newName)=(cR,cG,cB)
	
	avName = "W_Ave_dD_" + ReplaceString("_",pref,"")
	errName = ReplaceString("Ave", avName, "Err")
	AppendToGraph/W=dDPlot $avName
	ErrorBars/W=dDPlot $avName Y,wave=($errName,$errName)
	ModifyGraph/W=dDPlot lsize($avName)=2,rgb($avName)=(cR,cG,cB)
			
	avName = "W_Ave_MSD_" + ReplaceString("_",pref,"")
	errName = ReplaceString("Ave", avName, "Err")
	AppendToGraph/W=MSDPlot $avName
	ErrorBars/W=MSDPlot $avName Y,wave=($errName,$errName)
	ModifyGraph/W=MSDPlot lsize($avName)=2,rgb($avName)=(cR,cG,cB)
	
	avName = "W_Ave_DA_" + ReplaceString("_",pref,"")
	errName = ReplaceString("Ave", avName, "Err")
	AppendToGraph/W=DAPlot $avName
	ErrorBars/W=DAPlot $avName Y,wave=($errName,$errName)
	ModifyGraph/W=DAPlot lsize($avName)=2,rgb($avName)=(cR,cG,cB)
	
	// Tidy report
	DoWindow/F $layoutName
	// in case these are not captured as prefs
	LayoutPageAction size(-1)=(595, 842), margins(-1)=(18, 18, 18, 18)
	ModifyLayout units=0
	ModifyLayout frame=0,trans=1
	Execute /Q "Tile"
	TextBox/C/N=text0/F=0/A=RB/X=0.00/Y=0.00 ReplaceString("_",pref,"")
	DoUpdate
End

///////////////////////////////////////////////////////////////////////

///	@param	cond	number of conditions - determines size of box
Function myIO_Panel(cond)
	Variable cond
	// make global text wave to store paths
	Make/T/O/N=(cond) condWave
	Make/T/O/N=(cond) PathWave1,PathWave2
	DoWindow/K FilePicker
	NewPanel/N=FilePicker/K=1/W=(40,40,840,150+30*cond)
	// labelling of columns
	DrawText 30,30,"Name"
	DrawText 180,30,"Excel workbook for cell tracking data"
	DrawText 480,30,"Optional: workbook for stationary data" 
	// do it button
	Button DoIt,pos={680,70+30*cond},size={100,20},proc=DoItButtonProc,title="Do It"
	// insert rows
	String ButtonName1,ButtonName2,boxName0,boxName1,boxName2
	Variable i
	
	for(i = 0; i < cond; i += 1)
		boxName0 = "box0_" + num2str(i)
		buttonName1 = "file1_" + num2str(i)
		boxName1 = "box1_" + num2str(i)
		buttonName2 = "file2_" + num2str(i)
		boxName2 = "box2_" + num2str(i)
		// row label
		DrawText 10,68+i*30,num2str(i+1)
		// condition label
		SetVariable $boxName0,pos={30,53+i*30},size={100,14},value= condWave[i], title=" "
		// file button
		Button $buttonName1,pos={180,50+i*30},size={38,20},proc=ButtonProc,title="File"
		// file box
		SetVariable $boxName1,pos={220,53+i*30},size={240,14},value= PathWave1[i], title=" "
		// stationary button
		Button $buttonName2,pos={480,50+i*30},size={38,20},proc=ButtonProc,title="File"
		// stationary box
		SetVariable $boxName2,pos={520,53+i*30},size={240,14},value= PathWave2[i], title=" "
	endfor
End

// define buttons
Function ButtonProc(ctrlName) : ButtonControl
	String ctrlName

	Wave/T PathWave1,PathWave2
	Variable refnum
	String wNumStr, iiStr
	String expr="file([[:digit:]]+)\\w([[:digit:]]+)"
	SplitString/E=(expr) ctrlName, wNumStr, iiStr
	Variable wNum = str2num(wNumStr)
	Variable ii = str2num(iiStr)
	// get File Paths
	Open/D/R/F="*.xls*"/M="Select Excel Workbook" refNum
	if (strlen(S_FileName) == 0) // user cancelled or some error occured
		return -1
	endif
	if (wNum == 1)
		PathWave1[ii] = S_fileName
	else
		PathWave2[ii] = S_fileName
	endif
End

Function DoItButtonProc(ctrlName) : ButtonControl
	String ctrlName
 	
 	WAVE/T CondWave
	WAVE/T PathWave1
	Variable okvar = 0
	
	strswitch(ctrlName)	
		case "DoIt" :
			// check CondWave
			okvar = WaveChecker(CondWave)
			if (okvar == -1)
				Print "Error: Not all conditions have a name."
				break
			endif
			okvar = WaveChecker(PathWave1)
			if (okvar == -1)
				Print "Error: Not all conditions have a file to load."
				break
			else
				Migrate()
			endif
	endswitch	
End

STATIC function WaveChecker(TextWaveToCheck)
	Wave/T TextWaveToCheck
	Variable nRows = numpnts(TextWaveToCheck)
	Variable len
	
	Variable i
	
	for(i = 0; i < nRows; i += 1)
		len = strlen(TextWaveToCheck[i])
		if(len == 0)
			return -1
		elseif(numtype(len) == 2)
			return -1
		endif
	endfor
	return 1
End

///////////////////////////////////////////////////////////////////////

// Colours are taken from Paul Tol SRON stylesheet
// Define colours
StrConstant SRON_1 = "0x4477aa;"
StrConstant SRON_2 = "0x4477aa; 0xcc6677;"
StrConstant SRON_3 = "0x4477aa; 0xddcc77; 0xcc6677;"
StrConstant SRON_4 = "0x4477aa; 0x117733; 0xddcc77; 0xcc6677;"
StrConstant SRON_5 = "0x332288; 0x88ccee; 0x117733; 0xddcc77; 0xcc6677;"
StrConstant SRON_6 = "0x332288; 0x88ccee; 0x117733; 0xddcc77; 0xcc6677; 0xaa4499;"
StrConstant SRON_7 = "0x332288; 0x88ccee; 0x44aa99; 0x117733; 0xddcc77; 0xcc6677; 0xaa4499;"
StrConstant SRON_8 = "0x332288; 0x88ccee; 0x44aa99; 0x117733; 0x999933; 0xddcc77; 0xcc6677; 0xaa4499;"
StrConstant SRON_9 = "0x332288; 0x88ccee; 0x44aa99; 0x117733; 0x999933; 0xddcc77; 0xcc6677; 0x882255; 0xaa4499;"
StrConstant SRON_10 = "0x332288; 0x88ccee; 0x44aa99; 0x117733; 0x999933; 0xddcc77; 0x661100; 0xcc6677; 0x882255; 0xaa4499;"
StrConstant SRON_11 = "0x332288; 0x6699cc; 0x88ccee; 0x44aa99; 0x117733; 0x999933; 0xddcc77; 0x661100; 0xcc6677; 0x882255; 0xaa4499;"
StrConstant SRON_12 = "0x332288; 0x6699cc; 0x88ccee; 0x44aa99; 0x117733; 0x999933; 0xddcc77; 0x661100; 0xcc6677; 0xaa4466; 0x882255; 0xaa4499;"

/// @param hex		variable in hexadecimal
Function hexcolor_red(hex)
	Variable hex
	return byte_value(hex, 2) * 2^8
End

/// @param hex		variable in hexadecimal
Function hexcolor_green(hex)
	Variable hex
	return byte_value(hex, 1) * 2^8
End

/// @param hex		variable in hexadecimal
Function hexcolor_blue(hex)
	Variable hex
	return byte_value(hex, 0) * 2^8
End

/// @param data	variable in hexadecimal
/// @param byte	variable to determine R, G or B value
Static Function byte_value(data, byte)
	Variable data
	Variable byte
	return (data & (0xFF * (2^(8*byte)))) / (2^(8*byte))
End

STATIC Function CleanSlate()
	String fullList = WinList("*", ";","WIN:7")
	Variable allItems = ItemsInList(fullList)
	String name
	Variable i
 
	for(i = 0; i < allItems; i += 1)
		name = StringFromList(i, fullList)
		KillWindow/Z $name		
	endfor
	
	// Kill waves in root
	KillWaves/A/Z
	// Look for data folders and kill them
	DFREF dfr = GetDataFolderDFR()
	allItems = CountObjectsDFR(dfr, 4)
	for(i = 0; i < allItems; i += 1)
		name = GetIndexedObjNameDFR(dfr, 4, i)
		KillDataFolder $name		
	endfor
End

// This function reshuffles the plots so that they will be tiled (LR, TB) in the order that they were created
// From v 1.03 all plots are hidden so this function is commented out of workflow
Function OrderGraphs()
	String list = WinList("*", ";", "WIN:1")		// List of all graph windows
	Variable numWindows = ItemsInList(list)
	
	Variable i
	
	for(i = 0; i < numWindows; i += 1)
		String name = StringFromList(i, list)
		DoWindow /F $name
	endfor
End

// Function from aclight to retrieve #pragma version number
/// @param procedureWinTitleStr	This is the procedure window "LoadMigration.ipf"
Function GetProcedureVersion(procedureWinTitleStr)
	String procedureWinTitleStr
 
	// By default, all procedures are version 1.00 unless
	// otherwise specified.
	Variable version = 1.00
	Variable versionIfError = NaN
 
	String procText = ProcedureText("", 0, procedureWinTitleStr)
	if (strlen(procText) <= 0)
		return versionIfError		// Procedure window doesn't exist.
	endif
 
	String regExp = "(?i)(?:^#pragma|\\r#pragma)(?:[ \\t]+)version(?:[\ \t]*)=(?:[\ \t]*)([\\d.]*)"
 
	String versionFoundStr
	SplitString/E=regExp procText, versionFoundStr
	if (V_flag == 1)
		version = str2num(versionFoundStr)
	endif
	return version	
End