#pragma TextEncoding = "UTF-8"
#pragma rtGlobals=3				// Use modern global access method and strict wave access
#pragma DefaultTab={3,20,4}		// Set default tab width in Igor Pro 9 and later
#pragma version = 1.15		// version number of Migrate()
#pragma ModuleName = CellMigration
#include <Waves Average>
#include <ColorWaveEditor>

// CellMigration will analyse 2D cell migration in IgorPro
// Use ImageJ to track the cells. Outputs from tracking are saved either 
// 1) as sheets in an Excel Workbook, 1 per condition, or
// 2) as direct outputs from Manual Tracking, in csv format
// 
// Select CellMigr > Cell Migration...
//
// Tell the dialog how many conditions you want to load and the magnification and time resolution
// Next, give each condition a label (name) and then tell Igor where to find the data
// Either an Excel workbook (per condition) or a directory of CSVs (per condition)
// There is also the ability to define "offsetting data", in the case of XY drift during the experiment.
//
// For Excel workbooks:
// NOTE no headers in Excel file. Keep data to columns A-H, max of 2000 rows
// columns are
// A - 0 - ImageJ row
// B - 1 - Track No
// C - 2 - Slice No
// D - 3 - x (in px)
// E - 4 - y (in px)
// F - 5 - distance
// G - 6 - velocity (actually speed)
// H - 7 - pixel value

////////////////////////////////////////////////////////////////////////
// Menu items
////////////////////////////////////////////////////////////////////////
Menu "CellMigr"
	"Cell Migration...", /Q, SetUpMigration(0)
	"Superplot...", /Q, SetUpMigration(1)
	"Save Reports...", /Q, SaveAllReports()
	"Recolor Everything", /Q, RecolorAllPlotsWrapper()
	"Rerun Analysis", /Q, RerunAnalysis()
	Submenu "Manual tracking conversion"
		"Excel to Converted CSV", /Q, Excel2CSV()
		"CSV to Converted CSV", /Q, CSV2CSV()
	End
	"About CellMigration", /Q, AboutCellMigr()
End

////////////////////////////////////////////////////////////////////////
// Master functions and wrappers
////////////////////////////////////////////////////////////////////////
Function SetUpMigration(optVar)
	Variable optVar
	
	SetDataFolder root:
	// kill all windows and waves before we start
	CleanSlate()
	
	SetUp_Panel(optVar)
End

Function ProceedToMigrate()
	SetDataFolder root:
	WAVE/Z paramWave
	MakeColorWave(paramWave[0],"colorWave")
	if(paramWave[4] > 0)
		Superplot_Panel(paramWave[0],paramWave[4])
	else
		myIO_Panel(paramWave[0])
	endif
End


////////////////////////////////////////////////////////////////////////
// Main functions
////////////////////////////////////////////////////////////////////////
// Loads the data and performs migration analysis
Function Migrate()
	WAVE/Z paramWave = root:paramWave
	if(!WaveExists(paramWave))
		DoAlert 0, "Setup has failed. Missing paramWave."
		return -1
	endif
	
	// pick up global values needed
	Variable cond = paramWave[0]
	Variable tStep = paramWave[1]
	Variable pxSize = paramWave[2]
	Variable superPlot = 0, reps
	WAVE/Z colorWave = root:colorWave
	WAVE/T/Z condWave = root:condWave
	WAVE/T/Z condSplitWave = root:condSplitWave
	if(WaveExists(condSplitWave) == 1)
		if(cond < numpnts(condSplitWave))
			superPlot = 1
			cond = numpnts(condSplitWave)
			reps = cond / paramWave[0]
		endif
	endif
	// because the user may have used illegal characters in condWave, we make a clean version
	// for use in Igor and a copy of the original called labelWave to use in plots and layouts
	if(superPlot == 1)
		WAVE/T labelWave = CleanUpCondWave(condSplitWave)
		WAVE/T labelWave = CleanUpCondWave(condWave)
	else
		WAVE/T labelWave = CleanUpCondWave(condWave)
	endif
	
	// make summary plot windows
	String fullList = "cdPlot;ivPlot;ivHPlot;dDPlot;MSDPlot;DAPlot;angleHPlot"
	Variable nPlots = ItemsInList(fullList)
	String name
	Variable i,j
	
	for(i = 0; i < nPlots; i += 1)
		name = StringFromList(i, fullList)
		KillWindow/Z $name
		Display/N=$name/HIDE=1		
	endfor
	
	String dataFolderName = "root:data"
	NewDataFolder/O $dataFolderName // make root:data: but don't put anything in it yet
	
	String condName, pref
	Variable moviemax1, moviemax2
	
	for(i = 0; i < cond; i += 1)
		if(superPlot == 1)
			condName = condSplitWave[i]
		else
			condName = condWave[i]
		endif
		
		// make data folder for each condition
		dataFolderName = "root:data:" + condName
		NewDataFolder/O/S $dataFolderName
		// run other procedures
		moviemax1 = LoadMigration(i)
		moviemax2 = CorrectMigration(i)
		if(moviemax1 != moviemax2)
			if(moviemax2 == -1)
				print "No correction applied to", condName
			else
				print "Caution: different number of stationary tracks compared with real tracks."
			endif
		endif
		if(superPlot == 0)
			// for each condition go and make tracks and plot everything out
			MakeTracks(i)
		endif
		SetDataFolder root:
	endfor
	// if we are making a superplot, copy the data into folders named by condWave
	if(superPlot == 1)
		String sourceDF = ""
		cond = numpnts(condWave)
		for(i = 0; i < cond; i += 1)
			condName = condWave[i]
			// make data folder for each master condition
			dataFolderName = "root:data:" + condName
			NewDataFolder/O $dataFolderName
			for(j = 0; j < reps; j += 1)
				sourceDF = "root:data:" + condSplitWave[i * reps + j]
				// merge data into master condition folder
				DuplicateDataFolder/O=2 $sourceDF, $dataFolderName
			endfor
			SetDataFolder $dataFolderName
			// as in the main program: for each condition go and make tracks and plot everything out
			MakeTracks(i)
			SetDataFolder root:
		endfor
	endif
	
	// make the image quilt, spakline and joint histogram and then sort out the layouts
	Variable optDur = MakeImageQuilt(10) // this aims for a quilt of 100 = 10^2 tracks
	MakeJointHistogram(optDur)
	TidyCondSpecificLayouts()
	
	KillWindow/Z summaryLayout
	NewLayout/N=summaryLayout
	TidyUpSummaryLayout()
	
	// when we get to the end, print (pragma) version number
	Print "*** Executed Migrate v", GetProcedureVersion("CellMigration.ipf")
	KillWindow/Z FilePicker
End

// This function will load the tracking data
/// @param	ii	variable containing row number from condWave
Function LoadMigration(ii)
	Variable ii
	
	WAVE/T/Z condSplitWave = root:condSplitWave
	WAVE/T/Z condWave = root:condWave
	String condName
	if(WaveExists(condSplitWave) == 1)
		condName = condSplitWave[ii]
	else
		condName = condWave[ii]
	endif
	WAVE/T PathWave1 = root:PathWave1
	String pathString = PathWave1[ii]
	String sheet, prefix, matName, wList
	String fileList
	Variable moviemax,csvOrNot
	Variable i
	
	if(StringMatch(pathString, "*.xls*") == 1)
		// set variable to indicate Excel Workbook
		csvOrNot = 0
		// Works out what sheets are in Excel Workbook and then loads each.
		XLLoadWave/J=1 PathWave1[ii]
		fileList = S_value
	else
		// set variable to indicate csv file
		csvOrNot = 1
		// Work out what files are in directory
		NewPath/O/Q ExpDiskFolder, pathString
		fileList = IndexedFile(expDiskFolder,-1,".csv")
	endif
	fileList = SortList(fileList, ";", 16)
	moviemax = ItemsInList(fileList)
		
	for(i = 0; i < moviemax; i += 1)
		sheet = StringFromList(i, fileList)
		prefix = condName + "_c_" + num2str(i)
		matName = condName + "_" + num2str(i)
		if(csvOrNot == 0)
			XLLoadWave/S=sheet/R=(A1,H2000)/O/K=0/N=$prefix/Q PathWave1[ii]
		else
			LoadWave/A=$prefix/J/K=1/L={0,1,0,0,0}/O/P=expDiskFolder/Q sheet
		endif
		wList = wavelist(prefix + "*",";","")	// make matrix for each sheet
		Concatenate/O/KILL wList, $matName
		// now we need to check that the matrix is OK
		Wave matTrax = $matName
		// check we have a valid matrix with 8 columns
		CheckColumnsOfMatrix(matTrax)
		// make sure 1st point is -1
		matTrax[0][5,6] = -1
		// check distances and speeds are correct
		CheckDistancesAndSpeeds(matTrax)
	endfor	
		
	Print "*** Condition", condName, "was loaded from", pathString
	
	// return moviemax back to calling function for checking
	return moviemax
End

// This was added in v1.12 Dec 2018. At some point in the last year, the output
// of Manual Tracking changed so that there was no longer a first (0) column containing
// the row numbers. Add this column if that is the case.
STATIC Function CheckColumnsOfMatrix(matTrax)
	WAVE matTrax
	Variable numCols = DimSize(matTrax,1)
	if(numCols == 8)
		return 1
	elseif(numCols == 7)
		// insert new 0th column
		InsertPoints/M=1 0,1, MatTrax
		MatTrax[][0] = p+1
		return 0
	else
		Print NameOfWave(matTrax), "does not have 8 columns of data."
		return -1
	endif
End

// The purpose of this function is to work out whether the distances (and speeds) in the
// original data are correct. Currently it just corrects them rather than testing and correcting if needed.
STATIC Function CheckDistancesAndSpeeds(matTrax)
	WAVE matTrax
	
	WAVE/Z paramWave = root:paramWave
	Variable tStep = paramWave[1]
	Variable pxSize = paramWave[2]
	
	// make new distance column
	Duplicate/O/RMD=[][3,4]/FREE matTrax,tempDist // take offset coords
	Differentiate/METH=2/DIM=0 tempDist
	tempDist[][] = (matTrax[p][5] == -1) ? 0 : tempDist[p][q]
	MatrixOp/O/FREE tempNorm = sqrt(sumRows(tempDist * tempDist))
	tempNorm[] *= pxSize // convert to real distance
//	MatrixOp/O/FREE tempReal = sumcols(tempNorm - col(matTrax,5)) // for checking
	matTrax[][5] = (matTrax[p][5] == -1) ? -1 : tempNorm[p] // going to leave first point as -1
	// correct speed column
	matTrax[][6] = (matTrax[p][6] == -1) ? -1 : tempNorm[p] / tStep
	// make sure 1st point is -1
	matTrax[0][5,6] = -1
End

// This function will load the tracking data from an Excel Workbook
///	@param	ii	variable containing row number from condWave
Function CorrectMigration(ii)
	Variable ii
	
	WAVE/T/Z condSplitWave = root:condSplitWave
	WAVE/T/Z condWave = root:condWave
	String condName
	if(WaveExists(condSplitWave) == 1)
		condName = condSplitWave[ii]
	else
		condName = condWave[ii]
	endif
	WAVE/T PathWave2 = root:PathWave2
	String pathString = PathWave2[ii]
	Variable len = strlen(pathString)
	if(len == 0)
		return -1
	elseif(numtype(len) == 2)
		return -1
	endif
	
	String sheet, prefix, matName, wList, mName
	String fileList
	Variable moviemax,csvOrNot
	Variable i
	
	if(StringMatch(pathString, "*.xls*") == 1)
		// set variable to indicate Excel Workbook
		csvOrNot = 0
		// Works out what sheets are in Excel Workbook and then loads each.
		XLLoadWave/J=1 PathWave2[ii]
		fileList = S_value
	else
		// set variable to indicate csv file
		csvOrNot = 1
		// Work out what files are in directory
		NewPath/O/Q ExpDiskFolder, pathString
		fileList = IndexedFile(expDiskFolder,-1,".csv")
	endif
	fileList = SortList(fileList, ";", 16)
	moviemax = ItemsInList(fileList)
		
	for(i = 0; i < moviemax; i += 1)
		sheet = StringFromList(i,fileList)
		prefix = "stat_" + "c_" + num2str(i)	// use stat prefix
		matName = "stat_" + num2str(i)
		if(csvOrNot == 0)
			XLLoadWave/S=sheet/R=(A1,H2000)/O/K=0/N=$prefix/Q PathWave2[ii]
		else
			LoadWave/A=$prefix/J/K=1/L={0,1,0,0,0}/O/P=expDiskFolder/Q sheet
		endif
		wList = wavelist(prefix + "*",";","")	// make matrix for each sheet
		Concatenate/O/KILL wList, $matName
		Wave matStat = $matName
		// Find corresponding movie matrix
		mName = ReplaceString("stat_",matname,condName + "_")
		Wave matTrax = $mName
		OffsetAndRecalc(matStat,matTrax)
	endfor
	
	Print "*** Offset data for condition", condName, "was loaded from", pathString

	// return moviemax back to calling function for checking
	return moviemax
End

// This function uses matStat to offset matTrax
Function OffsetAndRecalc(matStat,matTrax)
	Wave matStat,matTrax
	// Work out offset for the stat_* waves
	Variable x0 = matStat[0][3]
	Variable y0 = matStat[0][4]
	matStat[][3] -= x0
	matStat[][4] -= y0
	MatrixOp/O/FREE mStat2 = col(matStat,2)
	Variable maxFrame = WaveMax(mStat2)
	Variable j // because i refers to rows
	
	// offsetting loop
	for(j = 1; j < maxFrame + 1; j += 1)
		FindValue/V=(j) mStat2
		if(V_Value == -1)
			x0 = 0
			y0 = 0
		else
			x0 = matStat[V_Value][3]
			y0 = matStat[V_Value][4]
		endif
		matTrax[][3] = (matTrax[p][2] == j) ? matTrax[p][3] - x0 : matTrax[p][3]
		matTrax[][4] = (matTrax[p][2] == j) ? matTrax[p][4] - y0 : matTrax[p][4]
	endfor
	WAVE/Z paramWave = root:paramWave
	Variable tStep = paramWave[1]
	Variable pxSize = paramWave[2]
	// make new distance column
	Duplicate/O/RMD=[][3,4]/FREE matTrax,tempDist // take offset coords
	Differentiate/METH=2 tempDist
	tempDist[][] = (matTrax[p][5] == -1) ? 0 : tempDist[p][q]
	MatrixOp/O/FREE tempNorm = sqrt(sumRows(tempDist * tempDist))
	tempNorm[] *= pxSize // convert to real distance
	matTrax[][5] = (matTrax[p][5] == -1) ? -1 : tempNorm[p] // going to leave first point as -1
	// correct speed column
	matTrax[][6] = (matTrax[p][6] == -1) ? -1 : tempNorm[p] / tStep
	// put 1st point as -1
	matTrax[0][5,6] = -1
End

// This function will make cumulative distance waves for each cell. They are called cd_*
///	@param	ii	variable containing row number from condWave
Function MakeTracks(ii)
	Variable ii
	
	WAVE/T condWave = root:condWave
	String condName = condWave[ii]
	WAVE/Z paramWave = root:paramWave
	Variable tStep = paramWave[1]
	Variable pxSize = paramWave[2]
	Variable minPoints = paramWave[5]
	WAVE/Z colorWave = root:colorWave
	WAVE/Z/T unitWave = root:unitWave
	
	String wList0 = WaveList(condName + "_*",";","") // find all matrices
	Variable nWaves = ItemsInList(wList0)
	
	Variable nTrack,nTrace=0
	String mName0, newName, plotName, avList, avName, errName
	Variable i, j
	
	String layoutName = condName + "_layout"
	KillWindow/Z $layoutName		// Kill the layout if it exists
	NewLayout/HIDE=1/N=$layoutName	

	// cumulative distance and plot over time	
	plotName = condName + "_cdplot"
	KillWindow/Z $plotName	// set up plot
	Display/N=$plotName/HIDE=1

	for(i = 0; i < nWaves; i += 1)
		mName0 = StringFromList(i,wList0)
		WAVE m0 = $mName0
		Duplicate/O/RMD=[][5,5] m0, $"tDistW"	// distance
		Duplicate/O/RMD=[][1,1] m0, $"tCellW"	// cell number
		WAVE tDistW,tCellW
		Redimension/N=-1 tDistW, tCellW // make 1D
		nTrack = WaveMax(tCellW)	// find maximum track number
		for(j = 1; j < (nTrack+1); j += 1)	// index is 1-based
			newName = "cd_" + mName0 + "_" + num2str(j)
			Duplicate/O tDistW, $newName
			WAVE w2 = $newName
			w2 = (tCellW[p] == j) ? tDistW[p] : NaN
			WaveTransform zapnans w2
			if(numpnts(w2) < minPoints)
				KillWaves/Z w2	// delete short tracks and any tracks that didn't exist
			else
				w2[0] = 0	// first point in distance trace is -1 so correct this
				Integrate/METH=0 w2	// make cumulative distance
				SetScale/P x 0,tStep, w2
				AppendtoGraph/W=$plotName $newName
				nTrace += 1
			endif
		endfor
		KillWaves/Z tDistW
	endfor
	Variable alphaLevel = DecideOpacity(nTrace)
	ModifyGraph/W=$plotName rgb=(colorWave[ii][0],colorWave[ii][1],colorWave[ii][2],alphaLevel)
	avList = Wavelist("cd*",";","WIN:"+ plotName)
	avName = "W_Ave_cd_" + condName
	errName = ReplaceString("Ave", avName, "Err")
	fWaveAverage(avList, "", 3, 1, avName, errName)
	AppendToGraph/W=$plotName $avName
	Label/W=$plotName left "Cumulative distance ("+unitWave[1]+")"
	Label/W=$plotName bottom "Time ("+unitWave[0]+")"
	ErrorBars/W=$plotName $avName SHADE= {0,0,(0,0,0,0),(0,0,0,0)},wave=($ErrName,$ErrName)
	ModifyGraph/W=$plotName lsize($avName)=2,rgb($avName)=(0,0,0)
	SetAxis/W=$plotName/A/N=1 left
	
	AppendLayoutObject/W=$layoutName graph $plotName
	
	// instantaneous speed over time	
	plotName = condName + "_ivplot"
	KillWindow/Z $plotName	// set up plot
	Display/N=$plotName/HIDE=1

	for(i = 0; i < nWaves; i += 1)
		mName0 = StringFromList(i,wList0)
		WAVE m0 = $mName0
		Duplicate/O/RMD=[][5,5] m0, $"tDistW"	// distance
		Duplicate/O/RMD=[][1,1] m0, $"tCellW"	// cell number
		WAVE tDistW,tCellW
		Redimension/N=-1 tDistW, tCellW // make 1D
		nTrack = WaveMax(tCellW)	// find maximum track number
		for(j = 1; j < (nTrack+1); j += 1)	// index is 1-based
			newName = "iv_" + mName0 + "_" + num2str(j)
			Duplicate/O tDistW, $newName
			WAVE w2 = $newName
			w2 = (tCellW[p] == j) ? tDistW[p] : NaN
			WaveTransform zapnans w2
			if(numpnts(w2) <= minPoints)
				KillWaves w2
			else
				w2[0] = 0	// first point in distance trace is -1, so correct this
				w2 /= tStep	// make instantaneous speed
				SetScale/P x 0,tStep, w2
				AppendtoGraph/W=$plotName $newName
			endif
		endfor
		KillWaves/Z tDistW
	endfor
	ModifyGraph/W=$plotName rgb=(colorWave[ii][0],colorWave[ii][1],colorWave[ii][2],alphaLevel)
	avList = Wavelist("iv*",";","WIN:"+ plotName)
	avName = "W_Ave_iv_" + condName
	errName = ReplaceString("Ave", avName, "Err")
	fWaveAverage(avList, "", 3, 1, avName, errName)
	AppendToGraph/W=$plotName $avName
	Label/W=$plotName left "Instantaneous Speed ("+unitWave[2]+")"
	Label/W=$plotName bottom "Time ("+unitWave[0]+")"
	ErrorBars/W=$plotName $avName SHADE= {0,0,(0,0,0,0),(0,0,0,0)},wave=($ErrName,$ErrName)
	ModifyGraph/W=$plotName lsize($avName)=2,rgb($avName)=(0,0,0)
	SetAxis/W=$plotName/A/N=1 left
	
	AppendLayoutObject/W=$layoutName graph $plotName
	// print a message to say how many valid tracks we have in this condition
	Print ItemsInList(avList), "valid tracks plotted for", condName
	
	plotName = condName + "_ivHist"
	KillWindow/Z $plotName	//set up plot
	Display/N=$plotName/HIDE=1
	
	Concatenate/O/NP avList, tempwave
	newName = "h_iv_" + condName	// note that this makes a name like h_iv_Ctrl
	// before v 1.15 we used sqrt((3*pxsize)^2)/tStep
	print wavemax(tempwave)
	Variable nBins = ceil(1 + log(numpnts(tempwave))/log(2))
	Variable binWidth = wavemax(tempwave)/nBins
	Make/O/N=(nBins) $newName
	Histogram/B={0,binWidth,nBins} tempwave,$newName
	AppendToGraph/W=$plotName $newName
	ModifyGraph/W=$plotName rgb=(colorWave[ii][0],colorWave[ii][1],colorWave[ii][2])
	ModifyGraph/W=$plotName mode=5,hbFill=4
	SetAxis/W=$plotName/A/N=1/E=1 left
	SetAxis/W=$plotName/A/N=1/E=1 bottom
	Label/W=$plotName left "Frequency"
	Label/W=$plotName bottom "Instantaneous Speed ("+unitWave[2]+")"
	KillWaves/Z tempwave
	
	AppendLayoutObject/W=$layoutName graph $plotName
	
	// plot out tracks
	plotName = condName + "_tkplot"
	KillWindow/Z $plotName	//set up plot
	Display/N=$plotName/HIDE=1
	
	Variable off
	
	for(i = 0; i < nWaves; i += 1)
		mName0 = StringFromList(i,wList0)
		WAVE m0 = $mName0
		Duplicate/O/RMD=[][3,3] m0, $"tXW"	//x pos
		Duplicate/O/RMD=[][4,4] m0, $"tYW"	//y pos
		Duplicate/O/RMD=[][1,1] m0, $"tCellW"	//track number
		WAVE tXW,tYW,tCellW
		Redimension/N=-1 tXW,tYW,tCellW		
		nTrack = WaveMax(tCellW)	//find maximum track number
		for(j = 1; j < (nTrack+1); j += 1)	//index is 1-based
			newName = "tk_" + mName0 + "_" + num2str(j)
			Duplicate/O tXW, $"w3"
			WAVE w3
			w3 = (tCellW[p] == j) ? w3[p] : NaN
			WaveTransform zapnans w3
			if(numpnts(w3) <= minPoints)
				KillWaves w3
			else
				off = w3[0]
				w3 -= off	//set to origin
				w3 *= pxSize
				// do the y wave
				Duplicate/O tYW, $"w4"
				WAVE w4
				w4 = (tCellW[p] == j) ? w4[p] : NaN
				WaveTransform zapnans w4
				off = w4[0]
				w4 -= off
				w4 *= pxSize
				Concatenate/O/KILL {w3,w4}, $newName
				Wave w5 = $newName
				AppendtoGraph/W=$plotName w5[][1] vs w5[][0]
			endif
		endfor
		Killwaves/Z tXW,tYW,tCellW //tidy up
	endfor
	ModifyGraph/W=$plotName rgb=(colorWave[ii][0],colorWave[ii][1],colorWave[ii][2],alphaLevel)
	// set these graph limits temporarily
	SetAxis/W=$plotName left -250,250
	SetAxis/W=$plotName bottom -250,250
	ModifyGraph/W=$plotName width={Plan,1,bottom,left}
	ModifyGraph/W=$plotName mirror=1
	ModifyGraph/W=$plotName grid=1
	ModifyGraph/W=$plotName gridRGB=(32767,32767,32767)
	
	AppendLayoutObject/W=$layoutName graph $plotName
	
	// calculate d/D directionality ratio
	plotName = condName + "_dDplot"
	KillWindow/Z $plotName	// setup plot
	Display/N=$plotName/HIDE=1
	
	String wName0, wName1
	Variable len
	wList0 = WaveList("tk_" + condName + "_*", ";","")
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
		AppendtoGraph/W=$plotName w2
	endfor
	ModifyGraph/W=$plotName rgb=(colorWave[ii][0],colorWave[ii][1],colorWave[ii][2],alphaLevel)
	avList = Wavelist("dD*",";","WIN:"+ plotName)
	avName = "W_Ave_dD_" + condName
	errName = ReplaceString("Ave", avName, "Err")
	fWaveAverage(avList, "", 3, 1, avName, errName)
	AppendToGraph/W=$plotName $avName
	Label/W=$plotName left "Directionality ratio (d/D)"
	Label/W=$plotName bottom "Time ("+unitWave[0]+")"
	ErrorBars/W=$plotName $avName SHADE= {0,0,(0,0,0,0),(0,0,0,0)},wave=($ErrName,$ErrName)
	ModifyGraph/W=$plotName lsize($avName)=2,rgb($avName)=(0,0,0)
	
	AppendLayoutObject/W=$layoutName graph $plotName
	
	// calculate MSD (overlapping method)
	plotName = condName + "_MSDplot"
	KillWindow/Z $plotName	//setup plot
	Display/N=$plotName/HIDE=1
	
	wList0 = WaveList("tk_" + condName + "_*", ";","")
	nWaves = ItemsInList(wList0)
	Variable k
	
	for(i = 0; i < nWaves; i += 1)
		wName0 = StringFromList(i,wList0)	// tk wave
		WAVE w0 = $wName0
		len = DimSize(w0,0)
		newName = ReplaceString("tk",wName0,"MSD")	// for results of MSD per cell
		Make/O/N=(len-1,len-1,2)/FREE tempMat0,tempMat1
		// make 2 3D waves. 0 is end point to measure MSD, 1 is start point
		// layers are x and y
		tempMat0[][][] = (p >= q) ? w0[p+1][r] : 0
		tempMat1[][][] = (p >= q) ? w0[p-q][r] : 0
		MatrixOp/O/FREE tempMat2 = (tempMat0 - tempMat1) * (tempMat0 - tempMat1))
		Make/O/N=(len-1)/FREE countOfMSDPnts = (len-1)-p
		MatrixOp/O $newName = sumcols(sumbeams(tempMat2))^t / countOfMSDPnts
		SetScale/P x 0,tStep, $newName
		AppendtoGraph/W=$plotName $newName
	endfor
	ModifyGraph/W=$plotName rgb=(colorWave[ii][0],colorWave[ii][1],colorWave[ii][2],alphaLevel)
	avList = Wavelist("MSD*",";","WIN:"+ plotName)
	avName = "W_Ave_MSD_" + condName
	errName = ReplaceString("Ave", avName, "Err")
	fWaveAverage(avList, "", 3, 1, avName, errName)
	AppendToGraph/W=$plotName $avName
	ModifyGraph/W=$plotName log=1
	SetAxis/W=$plotName/A/N=1 left
	len = numpnts($avName)*tStep
	SetAxis/W=$plotName bottom tStep,(len/2)
	Label/W=$plotName left "MSD"
	Label/W=$plotName bottom "Time ("+unitWave[0]+")"
	ErrorBars/W=$plotName $avName SHADE= {0,0,(0,0,0,0),(0,0,0,0)},wave=($errName,$errName)
	ModifyGraph/W=$plotName lsize($avName)=2,rgb($avName)=(0,0,0)
	
	AppendLayoutObject /W=$layoutName graph $plotName
	
	// calculate direction autocorrelation
	plotName = condName + "_DAplot"
	KillWindow/Z $plotName	// setup plot
	Display/N=$plotName/HIDE=1
	
	for(i = 0; i < nWaves; i += 1)
		wName0 = StringFromList(i,wList0)			// tk wave
		WAVE w0 = $wName0
		len = DimSize(w0,0)	// len is number of frames
		Differentiate/METH=2/DIM=0/EP=1 w0 /D=vWave // make vector wave (vWave). nVectors is len-1
		MatrixOp/O/FREE magWave = sqrt(sumrows(vWave * vWave)) // calculate magnitude of each vector
		vWave[][] /= magWave[p]	// normalise vectors
		newName = ReplaceString("tk",wName0,"DA")	// for results of DA per cell
		Make/O/N=(len-2,len-2,2)/FREE tempDAMat0,tempDAMat1
		tempDAMat0[][][] = (p >= q) ? vWave[p-q][r] : 0
		tempDAMat1[][][] = (p >= q) ? vWave[p+1][r] : 0
		MatrixOp/O/FREE dotWave = (tempDAMat0 * tempDAMat1)
		MatrixOp/O/FREE alphaWave = sumBeams(dotWave)
		// Make average. Previously we did this:
//		Make/O/N=(len-2)/FREE countOfDAPnts = (len-2)-p
//		MatrixOp/O $newName = sumcols(alphaWave)^t / countOfDAPnts
		// Now we need to get rid of NaNs in the alphaWave and count the non-NaN points
		MatrixOp/O/FREE alphaWave = replaceNans(alphaWave,0)
		Make/O/FREE/N=(dimsize(alphaWave,0),dimsize(alphaWave,1)) countOfDAPnts
		countOfDAPnts[][] = (abs(alphaWave[p][q]) > 0) ? 1 : 0
		MatrixOp/O $newName = sumcols(alphaWave)^t / sumCols(countOfDAPnts)^t
		SetScale/P x 0,tStep, $newName
		AppendtoGraph/W=$plotName $newName
	endfor
	Killwaves/Z vWave
	ModifyGraph/W=$plotName rgb=(colorWave[ii][0],colorWave[ii][1],colorWave[ii][2],alphaLevel)
	avList = Wavelist("DA*",";","WIN:"+ plotName)
	avName = "W_Ave_DA_" + condName
	errName = ReplaceString("Ave", avName, "Err")
	fWaveAverage(avList, "", 3, 1, avName, errName)
	AppendToGraph/W=$plotName $avName
	SetAxis/W=$plotName left -1,1
	Label/W=$plotName left "Direction autocorrelation"
	Label/W=$plotName bottom "Time ("+unitWave[0]+")"
	ErrorBars/W=$plotName $avName SHADE= {0,0,(0,0,0,0),(0,0,0,0)},wave=($errName,$errName)
	ModifyGraph/W=$plotName lsize($avName)=2,rgb($avName)=(0,0,0)
	
	AppendLayoutObject/W=$layoutName graph $plotName
	
	// calculate the angle distribution
	plotName = condName + "_anglePlot"
	KillWindow/Z $plotName	// setup plot
	Display/N=$plotName/HIDE=1
	wList0 = WaveList(condName + "_*",";","") // find all matrices
	nWaves = ItemsInList(wList0)
	Concatenate/O/NP=0 wList0, allTempW // make long matrix of all tracks
	Variable nSteps = dimsize(allTempW,0)
	Make/O/N=(nSteps)/FREE tempDistThreshW
	Make/O/D/N=(nSteps) angleWave = NaN
	// quality filter so that minimal steps are not analysed
	tempDistThreshW[] = (allTempW[p][5] > 4 * pxSize) ? 1 : 0
	Variable successVar = 0 
	// this will find angles for all tracks even short tracks
	// valid track length has a lower bound defined by user, minimum is 6 points (v. 1.15)
	// at tStep = 10 this will find max 4 angles in a track that is not found elsewhere 
	
	for(i = 0; i < nSteps; i += 1)
		// find a proper step
		if(tempDistThreshW[i] == 1)
			Make/O/N=(2,2)/FREE matAA,matBB
			// set first vector offset to origin (need to transpose later)
			matAA[][] = allTempW[p + (i-1)][q+3] - allTempW[i-1][q+3]
			for(j = i+1; j < nSteps; j += 1)
				if(allTempW[j][1] != allTempW[i][1])
					// check there is another proper step from the same cell
					successVar = 0
					break
				elseif(tempDistThreshW[j] == 1)
					// find a proper step from same cell and set second vector as this, offset to origin
					successVar = 1
					matBB[][] = allTempW[p + (j-1)][q+3] - allTempW[j-1][q+3]
					break
				else
					successVar = 0
				endif
			endfor
			
			if(successVar == 1)
				// matrices need transposing
				MatrixTranspose matAA
				MatrixTranspose matBB
				// find cos(theta)
				MatrixOp/O/FREE matCC = matAA . matBB / (sqrt(sum(matAA * matAA)) * sqrt(sum(matBB * matBB)))
				// angle in radians
				AngleWave[i] = acos(matCC[0])
			endif
		endif
	endfor
	KillWaves/Z allTempW
	// zapnans on AngleWave so I can count valid angles
	WaveTransform zapnans AngleWave
	newName = "h_angle_" + condName
	Make/N=41/O $newName
	Histogram/B={0,pi/40,41} angleWave,$newName
	AppendToGraph/W=$plotName $newName
	ModifyGraph/W=$plotName rgb=(colorWave[ii][0],colorWave[ii][1],colorWave[ii][2])
	ModifyGraph/W=$plotName mode=5, hbFill=4
	SetAxis/W=$plotName/A/N=1/E=1 left
	SetAxis/W=$plotName bottom 0,pi
	Make/O/N=5 axisW = {0,pi/4,pi/2,3*pi/4,pi}
	// vulgar fractions and pi as Unicode
	Make/O/N=5/T axisTW = {"0","\u00BC\u03C0","\u00BD\u03C0","\u00BE\u03C0","\u03C0"}
	ModifyGraph/W=$plotName userticks(bottom)={axisW,axisTW}	
	Label/W=$plotName left "Density"
	Label/W=$plotName bottom "Cell turning"
	
	AppendLayoutObject/W=$layoutName graph $plotName
	// print message about number of angles
	Print numpnts(AngleWave), "valid angles found from all tracks for", condName
	
	// Plot these averages to summary windows at the end
	avName = "W_Ave_cd_" + condName
	errName = ReplaceString("Ave", avName, "Err")
	AppendToGraph/W=cdPlot $avName
	ErrorBars/W=cdPlot $avName SHADE= {0,0,(0,0,0,0),(0,0,0,0)},wave=($errName,$errName)
	ModifyGraph/W=cdPlot lsize($avName)=2,rgb($avName)=(colorWave[ii][0],colorWave[ii][1],colorWave[ii][2])
	
	avName = "W_Ave_iv_" + condName
	errName = ReplaceString("Ave", avName, "Err")
	AppendToGraph/W=ivPlot $avName
	ErrorBars/W=ivPlot $avName SHADE= {0,0,(0,0,0,0),(0,0,0,0)},wave=($errName,$errName)
	ModifyGraph/W=ivPlot lsize($avName)=2,rgb($avName)=(colorWave[ii][0],colorWave[ii][1],colorWave[ii][2])
	
	newName = "h_iv_" + condName
	AppendToGraph/W=ivHPlot $newName
	ModifyGraph/W=ivHPlot rgb($newName)=(colorWave[ii][0],colorWave[ii][1],colorWave[ii][2])
	
	avName = "W_Ave_dD_" + condName
	errName = ReplaceString("Ave", avName, "Err")
	AppendToGraph/W=dDPlot $avName
	ErrorBars/W=dDPlot $avName SHADE= {0,0,(0,0,0,0),(0,0,0,0)},wave=($errName,$errName)
	ModifyGraph/W=dDPlot lsize($avName)=2,rgb($avName)=(colorWave[ii][0],colorWave[ii][1],colorWave[ii][2])
			
	avName = "W_Ave_MSD_" + condName
	errName = ReplaceString("Ave", avName, "Err")
	AppendToGraph/W=MSDPlot $avName
	ErrorBars/W=MSDPlot $avName SHADE= {0,0,(0,0,0,0),(0,0,0,0)},wave=($errName,$errName)
	ModifyGraph/W=MSDPlot lsize($avName)=2,rgb($avName)=(colorWave[ii][0],colorWave[ii][1],colorWave[ii][2])
	
	avName = "W_Ave_DA_" + condName
	errName = ReplaceString("Ave", avName, "Err")
	AppendToGraph/W=DAPlot $avName
	ErrorBars/W=DAPlot $avName SHADE= {0,0,(0,0,0,0),(0,0,0,0)},wave=($errName,$errName)
	ModifyGraph/W=DAPlot lsize($avName)=2,rgb($avName)=(colorWave[ii][0],colorWave[ii][1],colorWave[ii][2])
	
	newName = "h_angle_" + condName
	AppendToGraph/W=angleHPlot $newName
	ModifyGraph/W=angleHPlot rgb($newName)=(colorWave[ii][0],colorWave[ii][1],colorWave[ii][2])
End

///	@param	plotString	String such as "*_tkPlot" to determine which plot get rescaled
///	@param	limitVar	Variable containing the furthest point
STATIC Function RescalePlotsToLimits(plotString,limitVar)
	String plotString
	Variable limitVar
	// previously a temporary limit of -250,250 was set to all tkPlots and then expanded here if necessary
	// as of v 1.15, we just use the furthest point
	if(limitVar > 1000)
		limitVar = ceil(limitVar / 100) * 100
	elseif(limitVar >= 10 && limitVar < 100)
		limitVar = ceil(limitVar / 10) * 10
	elseif(limitVar >= 1 && limitVar < 10)
		limitVar = ceil(limitVar / 1) * 1
	elseif(limitVar >= 0.1 && limitVar < 1)
		limitVar = ceil(limitVar / 0.1) * 0.1
	elseif(limitVar < 0.1)
		limitVar = limitVar
	else
		limitVar = ceil(limitVar / 50) * 50 // we expect values of 150-300
	endif
	String plotList = WinList(plotString,";","WIN:1")
	String plotName
	Variable i
	for(i = 0; i < ItemsInList(plotList); i += 1)
		plotName = StringFromList(i,plotList)
		SetAxis/W=$plotName left -limitVar,limitVar
		SetAxis/W=$plotName/Z bottom -limitVar,limitVar
		SetAxis/W=$plotName/Z top -limitVar,limitVar
	endfor
	
	return 1
End

// This function will make ImageQuilts and sparklines of 2D tracks for all conditions
/// @param qSize	Variable to indicate desired size of image quilt (qSize^2 tracks)
Function MakeImageQuilt(qSize)
	Variable qSize
	
	WAVE/T condWave = root:condWave
	Variable cond = numpnts(condWave)
	Wave paramWave = root:paramWave
	Variable tStep = paramWave[1]
	Variable pxSize = paramWave[2]
	Wave colorWave = root:colorWave
	String condName, dataFolderName, wName
	Variable longestCond = 0 , mostFrames = 0
	
	Variable i
	
	for(i = 0; i < cond; i += 1)
		condName = condWave[i]
		dataFolderName = "root:data:" + condName
		SetDataFolder datafolderName
		mostFrames = FindSolution()
		longestCond = max(longestCond,mostFrames)
	endfor
	SetDataFolder root:
	// Now they're all done, cycle again to find optimum quilt size
	Make/O/N=(longestCond,qSize+1,cond)/FREE optiMat
	for(i = 0; i < cond; i += 1)
		condName = condWave[i]
		wName = "root:data:" + condName + ":solutionWave"
		Wave w0 = $wName
		optiMat[][][i] = (w0[p][0] >= q^2) ? 1 : 0
	endfor
	optiMat /= cond
	// make a 1D wave where row = qSize and value = frames that can be plotted for all cond
	MatrixOp/O/FREE quiltSizeMat = sumcols(floor(sumBeams(optiMat)))^t
	// find optimum
	quiltSizeMat *= p^2
	WaveStats/Q quiltSizeMat
	Variable optQSize = V_maxRowLoc
	Variable optDur = (V_max / V_maxRowLoc^2) - 1 // because 0-based
	Print qSize, "x", qSize, "quilt requested.", optQSize, "x", optQSize, "quilt with", optDur, "frames shown (", optDur * tStep, "min)."
	
	String plotName,sampleWName
	Variable startVar,endVar,xShift,yShift
	Variable spaceVar = WorkOutSpacing(pxSize)
	Variable j,k
	
	for(i = 0; i < cond; i += 1)
		condName = condWave[i]
		dataFolderName = "root:data:" + condName
		SetDataFolder datafolderName
		// make image quilt for each condition
		plotName = condName + "_quilt"
		KillWindow/Z $plotName
		Display/N=$plotName/HIDE=1
		WAVE segValid, trackDurations
		WAVE/T trackNames
		segValid[] = (trackDurations[p] > optDur * tStep) ? p : NaN
		WaveTransform zapnans segValid
		StatsSample/N=(optQSize^2) segValid
		WAVE/Z W_Sampled
		sampleWName = "segSelected_" + condName
		Duplicate/O W_Sampled, $sampleWName
		Wave segSelected = $sampleWName
		Make/O/N=(optQSize^2)/T segNames
		Make/O/N=(optQSize^2) segLengths
		for(j = 0; j < optQSize^2; j += 1)
			segNames[j] = trackNames[segSelected[j]]
			wName = ReplaceString("tk_",segNames[j],"cd_") // get cum dist wave name
			Wave cdW0 = $wName
			segLengths[j] = cdW0[optDur] // store cum dist at point optDur
		endfor
		Sort segLengths, segLengths, segNames
		// plot segNamed waves out
		Make/O/N=(optQSize^2*(optDur+1),2) quiltBigMat = NaN
		for(j = 0; j < optQSize^2; j += 1)
			wName = segNames[j]
			Wave tkW0 = $wName
			// put each track into the big quilt wave leaving a NaN between each
			startVar = j * optDur + (j * 1)
			endVar = startVar + optDur - 1
			quiltBigMat[startVar,endVar][] = tkW0[p-startVar][q]
			xShift = mod(j,optQSize) * spaceVar
			yShift = floor(j/optQSize) * spaceVar
			quiltBigMat[startVar,endVar][0] += xShift
			quiltBigMat[startVar,endVar][1] += yShift
		endfor
		// Add to plot and then format
		AppendToGraph/W=$plotName quiltBigMat[][1] vs quiltBigMat[][0]
		SetAxis/W=$plotName left (optQsize+1.5) * spaceVar,-2.5*spaceVar
		SetAxis/W=$plotName bottom -2.5*spaceVar,(optQsize+1.5) * spaceVar
		ModifyGraph/W=$plotName width={Aspect,1}
		ModifyGraph/W=$plotName manTick={0,spaceVar,0,0},manMinor={0,0}
		ModifyGraph/W=$plotName noLabel=2,mirror=1,standoff=0,tick=3
		ModifyGraph/W=$plotName grid=1,gridRGB=(34952,34952,34952)
		ModifyGraph axRGB=(65535,65535,65535)
		ModifyGraph/W=$plotName rgb=(colorWave[i][0],colorWave[i][1],colorWave[i][2])
		ModifyGraph/W=$plotName margin=14
		// Append to appropriate layout (page 2)
		String layoutName = condName + "_layout"
		LayoutPageAction/W=$layoutName appendPage
		AppendLayoutObject/W=$layoutName/PAGE=(2) graph $plotName
		ModifyLayout/W=$layoutName/PAGE=(2) left($plotName)=21,top($plotName)=291,width($plotName)=261,height($plotName)=261
		// make sparkline graphic
		plotName = condName + "_sprkln"
		KillWindow/Z $plotName
		Display/N=$plotName/HIDE=1
		// plot the diagonal of segNamed waves out laterally
		Make/O/N=(optQSize*(optDur+1),2) sprklnBigMat = NaN
		Variable theta
		k = 0
		for(j = 0; j < optQSize^2; j += optQsize+1)
			wName = segNames[j]
			Wave tkW0 = $wName
			Duplicate/O/FREE tkW0, sprkW0
			theta = (1.5 * pi) - atan2(sprkW0[optDur-1][1],sprkW0[optDur-1][0])
			Make/O/N=(2,2)/FREE rotMat = {{cos(theta),-sin(theta)},{sin(theta),cos(theta)}}
			MatrixMultiply sprkW0, rotMat
			WAVE/Z M_product
			// put each track into the big quilt wave leaving a NaN between each
			startVar = k * optDur + (k * 1)
			endVar = startVar + optDur - 1
			sprklnBigMat[startVar,endVar][] = M_Product[p-startVar][q]
			xShift = mod(k,optQSize) * spaceVar
			sprklnBigMat[startVar,endVar][0] += xShift
			k += 1
		endfor
		KillWaves/Z M_product
		// Add to plot and then format
		AppendToGraph/W=$plotName sprklnBigMat[][1] vs sprklnBigMat[][0]
		SetAxis/W=$plotName left 0.75 * spaceVar,-2.5*spaceVar
		SetAxis/W=$plotName bottom -0.5*spaceVar,(optQsize+0.5) * spaceVar
		ModifyGraph/W=$plotName width={Plan,1,bottom,left}
		ModifyGraph/W=$plotName manTick={0,spaceVar,0,0},manMinor={0,0}
		ModifyGraph/W=$plotName noLabel=2,mirror=1,standoff=0,tick=3
		ModifyGraph/W=$plotName grid=1,gridRGB=(34952,34952,34952)
		ModifyGraph axRGB=(65535,65535,65535)
		ModifyGraph/W=$plotName rgb=(colorWave[i][0],colorWave[i][1],colorWave[i][2])
		ModifyGraph/W=$plotName margin=14
		SetDrawLayer/W=$plotName UserBack
		SetDrawEnv/W=$plotName xcoord= prel,ycoord= left,linefgc= (21845,21845,21845),dash= 1
		DrawLine/W=$plotName 0,0,1,0
		SetDrawLayer/W=$plotName UserFront
		// Append to appropriate layout (page 2)
		AppendLayoutObject/W=$layoutName/PAGE=(2) graph $plotName
		ModifyLayout/W=$layoutName/PAGE=(2) left($plotName)=21,top($plotName)=558,width($plotName)=542,height($plotName)=180
	endfor
	SetDataFolder root:
	return optDur
End

Function FindSolution()
	String wList = WaveList("tk_*",";","")
	Variable nWaves = ItemsInList(wList)
	Make/O/N=(nWaves)/T trackNames
	Make/O/N=(nWaves) trackDurations, segValid
	Wave paramWave = root:paramWave
	Variable tStep = paramWave[1]
	String wName
	
	Variable i
	
	for(i = 0; i < nWaves; i += 1)
		wName = StringFromList(i,wList)
		trackNames[i] = wName
		Wave w0 = $wName
		trackDurations[i] = (dimsize(w0,0) - 1) * tStep
	endfor
	
	// how many are longer than x hrs?
	Variable mostFrames = round(WaveMax(trackDurations) / tStep)
	Make/O/N=(mostFrames,nWaves) solutionMat
	// Find tracks that are longer than a given length of time
	solutionMat[][] = (trackDurations[q] > p * tStep) ? 1 : 0
	MatrixOp/O solutionWave = sumRows(solutionMat)
	return mostFrames
End

// This function will make Joint Histograms of 2D tracks for all conditions
// It uses the segValid calculation from MakeImageQuilts to find the correct tracks to plot out
// Two JH are made. One of the segValid camples for optDur length in their original state
// Second is a bootstrap of 50000 resamples of segValid tracks for optDur randomly oriented
Function MakeJointHistogram(optDur)
	Variable optDur
	
	WAVE/T condWave = root:condWave
	Variable cond = numpnts(condWave)
	Wave paramWave = root:paramWave
	Variable tStep = paramWave[1]
	Variable pxSize = paramWave[2]
	Wave colorWave = root:colorWave
	String condName, dataFolderName, wName, plotName
	Variable leastValid = 1000
	
	Variable i,j
	
	// find lowest number of valid tracks in all conditions
	// Valid tracks are tracks with a length that could be plotted in the quilt
	for(i = 0; i < cond; i += 1)
		condName = condWave[i]
		dataFolderName = "root:data:" + condName
		SetDataFolder datafolderName
		WAVE segValid
		leastValid = min(leastValid,numpnts(segValid))
	endfor
	
	String sampleWName
	Variable startVar,endVar
	Variable furthestPoint,theta
	Variable boot = 50000
	// now concatenate leastValid number of tracks from each condition
	for(i = 0; i < cond; i += 1)
		Make/O/N=(2,2)/FREE rotMat
		condName = condWave[i]
		dataFolderName = "root:data:" + condName
		SetDataFolder datafolderName
		WAVE/T trackNames
		WAVE segValid
		
		// take a random sample of leastValid number of tracks from each condition
		StatsSample/N=(leastValid) segValid
		WAVE/Z W_Sampled
		sampleWName = "segJHSelected_" + condName
		Duplicate/O W_Sampled, $sampleWName
		Wave segJHSelected = $sampleWName
		Make/O/N=(leastValid)/T segJHNames
		Make/O/N=(leastValid*optDur,2) bigTk
		for(j = 0; j < leastValid; j += 1)
			wName = trackNames[segJHSelected[j]]
			segJHNames[j] = wName
			Wave tkW0 = $wName
			startVar = j * optDur
			endVar = startVar + optDur - 1
			bigTk[startVar,endVar][] = tkW0[p-startVar][q]
		endfor
		
		// bootstrap leastValid number of tracks from each condition
		StatsResample/N=(boot) segValid
		WAVE/Z W_Resampled
		sampleWName = "segBJHSelected_" + condName
		Duplicate/O W_Resampled, $sampleWName
		Wave segBJHSelected = $sampleWName
		Make/O/N=(boot)/T segBJHNames
		Make/O/N=(boot*optDur,2) bigBTk
		for(j = 0; j < boot; j += 1)
			wName = trackNames[segBJHSelected[j]]
			segBJHNames[j] = wName
			Wave tkW0 = $wName
			startVar = j * optDur
			endVar = startVar + optDur - 1
			Duplicate/O/FREE tkW0,tempM0
			theta = pi*enoise(1)
			rotMat = {{cos(theta),-sin(theta)},{sin(theta),cos(theta)}}
			MatrixMultiply tempM0, rotMat
			WAVE/Z M_Product
			bigBTk[startVar,endVar][] = M_Product[p-startVar][q]
		endfor		
		// find the furthest point in x or y in either direction for all conditions
		furthestPoint = max(furthestPoint,wavemax(bigBTk),abs(wavemin(bigBTk)))
		KillWaves/Z W_Sampled,W_Resampled
	endfor
	
	// set up the color table and bin waves for joint histograms
	SetDataFolder root:
	LoadNiceCTableW()
	// we'll use a reduction factor of 20
	Variable binSize = 20 * pxSize
	Variable leftTop = (binSize^2 * (ceil(furthestPoint / binsize^2) + 1)) + (binSize / 2)
	Variable nBins = (binsize^2 * (((ceil(furthestPoint / binsize^2) + 1) * 2)) / binSize) + 2
	Make/O/N=(nBins)/FREE theBinsWave = (p * binSize) - leftTop
	Variable highestPoint = 0,highestBPoint = 0
	String JHName,BJHName
	
	for(i = 0; i < cond; i += 1)
		condName = condWave[i]
		dataFolderName = "root:data:" + condName
		SetDataFolder datafolderName
		// do first JH
		WAVE bigTk
		Duplicate/O/RMD=[][0] bigTk,xData
		Duplicate/O/RMD=[][1] bigTk,yData
		WAVE/Z xData, yData
		JointHistogram/XBWV=theBinsWave/YBWV=theBinsWave xData,yData
		plotName = condName + "_JHplot"
		WAVE/Z M_JointHistogram
		JHName = "segJHMat"
		Duplicate/O M_JointHistogram, $JHName
		KillWindow/Z $plotName
		NewImage/N=$plotName/HIDE=1 $JHName
		ModifyImage/W=$plotName $JHName ctab= {1,*,root:Packages:ColorTables:Moreland:SmoothCoolWarm256,1},log=1,minRGB=NaN,maxRGB=0
		ModifyGraph/W=$plotName width={Aspect,1}
		ModifyGraph axRGB=(34952,34952,34952),tlblRGB=(34952,34952,34952),alblRGB=(34952,34952,34952)
		// scale the image
		SetScale/P x -leftTop,binSize,"", $JHName
		SetScale/P y -leftTop,binSize,"", $JHName
		SetAxis/W=$plotName left -250,250
		SetAxis/W=$plotName top -250,250
		// find the max point in z of JHs
		highestPoint = max(highestPoint,WaveMax($JHName))
		// Append 1st JH to layout
		String layoutName = condName + "_layout"
		AppendLayoutObject/W=$layoutName/PAGE=(2) graph $plotName
		ModifyLayout/W=$layoutName/PAGE=(2) left($plotName)=21,top($plotName)=21,width($plotName)=261,height($plotName)=261
		
		// now do BJH
		WAVE bigBTk
		Duplicate/O/RMD=[][0] bigBTk,xData
		Duplicate/O/RMD=[][1] bigBTk,yData
		JointHistogram/XBWV=theBinsWave/YBWV=theBinsWave xData,yData
		plotName = condName + "_BJHplot"
		BJHName = "segBJHMat"
		Duplicate/O M_JointHistogram, $BJHName
		KillWindow/Z $plotName
		NewImage/N=$plotName/HIDE=1 $BJHName
		ModifyImage/W=$plotName $BJHName ctab= {1,*,root:Packages:ColorTables:Moreland:SmoothCoolWarm256,1},log=1,minRGB=NaN,maxRGB=0
		ModifyGraph/W=$plotName width={Aspect,1}
		ModifyGraph axRGB=(34952,34952,34952),tlblRGB=(34952,34952,34952),alblRGB=(34952,34952,34952)
		// scale the image
		SetScale/P x -leftTop,binSize,"", $BJHName
		SetScale/P y -leftTop,binSize,"", $BJHName
		SetAxis/W=$plotName left -250,250
		SetAxis/W=$plotName top -250,250
		highestBPoint = max(highestBPoint,WaveMax($BJHName))
		// now append the BJH
		AppendLayoutObject/W=$layoutName/PAGE=(2) graph $plotName
		ModifyLayout/W=$layoutName/PAGE=(2) left($plotName)=291,top($plotName)=21,width($plotName)=261,height($plotName)=261
		
		KillWaves/Z xData,yData, M_JointHistogram, bigTk,bigBTk
	endfor
	// convert highest points to ceil log10 value
	highestPoint = ceil(log(highestPoint))
	highestBPoint = ceil(log(highestBPoint))
	// now go back around a scale the joint histograms to the same max and add colorscale
	for(i = 0; i < cond; i += 1)
		condName = condWave[i]
		dataFolderName = "root:data:" + condName
		SetDataFolder datafolderName
		plotName = condName + "_JHplot"
		ModifyImage/W=$plotName $JHName ctab= {1,10^highestPoint,root:Packages:ColorTables:Moreland:SmoothCoolWarm256,0},log=1,minRGB=NaN,maxRGB=0
		ColorScale/W=$plotName/C/N=text0/F=0/B=1/A=RB/X=0.00/Y=1 vert=0,widthPct=50,heightPct=5,frame=0.00,image=$JHName,log=1,tickLen=2.00
		ModifyGraph/W=$plotName gfSize=8

		plotName = condName + "_BJHplot"
		ModifyImage/W=$plotName $BJHName ctab= {1,10^highestBPoint,root:Packages:ColorTables:Moreland:SmoothCoolWarm256,0},log=1,minRGB=NaN,maxRGB=0
		ColorScale/W=$plotName/C/N=text0/F=0/B=1/A=RB/X=0.00/Y=1 vert=0,widthPct=50,heightPct=5,frame=0.00,image=$BJHName,log=1,tickLen=2.00
		ModifyGraph/W=$plotName gfSize=8
	endfor
	// rescale tk, JH and BJH plots
	RescalePlotsToLimits("*_tkplot",furthestPoint)
	RescalePlotsToLimits("*_JHplot",furthestPoint)
	RescalePlotsToLimits("*_BJHplot",furthestPoint)
	SetDataFolder root:
End

// Function to sort out the summary layout
// Traces have been added and colored as we went along, but now to format them
// and add some summary graphs
Function TidyUpSummaryLayout()
	SetDataFolder root:
	WAVE/Z/T condWave = root:condWave
	Variable cond = numpnts(condWave)
	Wave paramWave = root:paramWave
	Variable tStep = paramWave[1]
	Variable segmentLength = paramWave[3]
	Wave colorWave = root:colorWave
	WAVE/Z/T labelWave = root:labelWave
	WAVE/Z/T unitWave = root:unitWave
	// will we make a superplot?
	WAVE/T/Z condSplitWave = root:condSplitWave
	Variable superPlot
	if(!WaveExists(condSplitWave))
		superPlot = 0
	else
		superPlot = 1
	endif

	// Tidy up summary windows
	SetAxis/W=cdPlot/A/N=1 left
	Label/W=cdPlot left "Cumulative distance ("+unitWave[1]+")"
	Label/W=cdPlot bottom "Time ("+unitWave[0]+")"
		AppendLayoutObject /W=summaryLayout graph cdPlot
	SetAxis/W=ivPlot/A/N=1 left
	Label/W=ivPlot left "Instantaneous Speed ("+unitWave[2]+")"
	Label/W=ivPlot bottom "Time ("+unitWave[0]+")"
		AppendLayoutObject /W=summaryLayout graph ivPlot
	SetAxis/W=ivHPlot/A/N=1/E=1 left
	SetAxis/W=ivHPlot/A/N=1/E=1 bottom
	Label/W=ivHPlot left "Frequency"
	Label/W=ivHPlot bottom "Instantaneous Speed ("+unitWave[2]+")"
	ModifyGraph/W=ivHPlot mode=6
		AppendLayoutObject /W=summaryLayout graph ivHPlot
	Label/W=dDPlot left "Directionality ratio (d/D)"
	Label/W=dDPlot bottom "Time ("+unitWave[0]+")"
		AppendLayoutObject /W=summaryLayout graph dDPlot
	ModifyGraph/W=MSDPlot log=1
	SetAxis/W=MSDPlot/A/N=1 left
	Wave w = WaveRefIndexed("MSDPlot",0,1)
	SetAxis/W=MSDPlot bottom tStep,((numpnts(w) * tStep)/2)
	Label/W=MSDPlot left "MSD"
	Label/W=MSDPlot bottom "Time ("+unitWave[0]+")"
		AppendLayoutObject /W=summaryLayout graph MSDPlot
	SetAxis/W=DAPlot left 0,1
	Wave w = WaveRefIndexed("DAPlot",0,1)
	SetAxis/W=DAPlot bottom 0,((numpnts(w)*tStep)/2)
	Label/W=DAPlot left "Direction autocorrelation"
	Label/W=DAPlot bottom "Time ("+unitWave[0]+")"
		AppendLayoutObject /W=summaryLayout graph DAPlot
	SetAxis/W=angleHPlot/A/N=1/E=1 left
	SetAxis/W=angleHPlot bottom 0,pi
	ModifyGraph/W=angleHPlot mode=6
	Make/O/N=5 axisW = {0,pi/4,pi/2,3*pi/4,pi}
	Make/O/N=5/T axisTW = {"0","\u00BD\u03C0","\u00BD\u03C0","\u00BE\u03C0","\u03C0"}
	ModifyGraph/W=angleHPlot userticks(bottom)={axisW,axisTW}	
	Label/W=angleHPlot left "Density"
	Label/W=angleHPlot bottom "Cell turning"
		AppendLayoutObject /W=summaryLayout graph angleHPlot
	
	// average the speed data and do strava calc from all conditions
	String wList, speedName, stravaName, wName, condName, datafolderName
	Variable nTracks, last, mostTracks, stravaOK
	Variable i, j
	
	for(i = 0; i < cond; i += 1)
		condName = condWave[i]
		dataFolderName = "root:data:" + condName
		SetDataFolder $dataFolderName
		wList = WaveList("cd_" + condName + "_*", ";","")
		nTracks = ItemsInList(wList)
		speedName = "sum_Speed_" + condName
		stravaName = "sum_Strava_" + condName
		Make/O/N=(nTracks) $speedName, $stravaName
		Wave speedW = $speedName
		Wave stravaW = $stravaName
		for(j = 0; j < nTracks; j += 1)
			wName = StringFromList(j,wList)
			Wave w1 = $wName
			last = numpnts(w1) - 1	// finds last row (max cumulative distance)
			speedW[j] = w1[last]/(last*tStep)	// calculates speed
			stravaW[j] = StravaCalc(w1,segmentLength)
		endfor
		stravaOK += checkStravaW(stravaW)
		mostTracks = max(mostTracks,nTracks)
	endfor
	
	KillWindow/Z SpeedPlot
	Display/N=SpeedPlot/HIDE=1
	KillWindow/Z StravaPlot
	Display/N=StravaPlot/HIDE=1
	// now store the values in a blank matrix for category-style box/violinplots
	for(i = 0; i < cond; i += 1)
		condName = condWave[i]
		dataFolderName = "root:data:" + condName
		SetDataFolder $dataFolderName
		speedName = "sum_Speed_" + condName
		Wave speedW = $speedName
		Make/O/N=(mostTracks,cond) $(ReplaceString("sum_S",speedName,"sum_MatS"))=NaN
		Wave sum_MatSpeed = $(ReplaceString("sum_S",speedName,"sum_MatS"))
		sum_MatSpeed[0,numpnts(speedW)-1][i] = speedW[p]
		stravaName = "sum_Strava_" + condName
		BuildBoxOrViolinPlot(sum_MatSpeed,"SpeedPlot",i)
		if(stravaOK == cond)
			Wave stravaW = $stravaName
			Make/O/N=(mostTracks,cond) $(ReplaceString("sum_S",stravaName,"sum_MatS"))=NaN
			Wave sum_MatStrava = $(ReplaceString("sum_S",stravaName,"sum_MatS"))
			sum_MatStrava[0,numpnts(stravaW)-1][i] = stravaW[p]
			BuildBoxOrViolinPlot(sum_MatStrava,"StravaPlot", i)
		endif
	endfor
	Label/W=SpeedPlot left "Average speed ("+unitWave[2]+")"
	SetAxis/A/N=1/E=1/W=SpeedPlot left
	ModifyGraph/W=SpeedPlot toMode=-1
	AppendLayoutObject /W=summaryLayout graph SpeedPlot
	
	if(stravaOK == cond)
		Label/W=StravaPlot left "Fastest "+ num2str(segmentLength) + " "+unitWave[1]+" ("+unitWave[0]+")"
		SetAxis/A/N=1/E=1/W=StravaPlot left
		ModifyGraph/W=StravaPlot toMode=-1
		AppendLayoutObject /W=summaryLayout graph StravaPlot
	else
		KillWindow/Z StravaPlot
	endif
	
	// now make the superplot
	// this part is quite long and could move to its own function
	if(superPlot == 1)
		KillWindow/Z SuperPlot_cond
		Display/N=SuperPlot_cond/HIDE=1
		KillWindow/Z SuperPlot_rep
		Display/N=SuperPlot_rep/HIDE=1
		Variable nBin, binSize, loBin, hiBin
		Variable nRow, firstRow, inBin, maxNBin
		Variable groupWidth = 0.4 // this is hard-coded for now
		Variable alphaLevel = DecideOpacity(mostTracks)
		Variable reps = numpnts(condSplitWave) / numpnts(condWave)
		MakeColorWave(reps,"colorSplitWave")
		WAVE/Z colorSplitWave = root:colorSplitWave
		MakeColorWave(reps,"colorSplitWaveA", alpha = alphaLevel)
		WAVE/Z colorSplitWaveA = root:colorSplitWaveA
		String aveName, errName
		Make/O/N=(reps,cond)/FREE collatedMat
		for(i = 0; i < cond; i += 1)
			condName = condWave[i]
			// go to data folder for each master condition
			dataFolderName = "root:data:" + condName
			SetDataFolder $dataFolderName
			wName = "sum_Speed_" + condName
			Wave w = $wName
			Duplicate/O/FREE w, tempW, keyW
			keyW[] = p
			Sort tempW, tempW, keyW
			nRow = numpnts(w)
			// make wave to store the counts per bin
			Make/O/N=(nRow)/I/FREE spSum_IntWave
			Make/O/N=(nRow)/FREE spSum_nWave
			Make/O/N=(nRow) spSum_xWave = i
			// make a histogram of w so that we can find the modal bin
			Histogram/B=5 w
			WAVE/Z W_Histogram
			nBin = numpnts(W_Histogram)
			binSize = deltax(W_Histogram)
			maxNbin = WaveMax(W_Histogram) + 1
			for(j = 0; j < nBin; j += 1)
				loBin = WaveMin(tempW) + (j * binSize)
				hiBin = WaveMin(tempW) + ((j + 1) * binSize)
				if(j == 0)
					loBin = 0
				elseif( j == nBin - 1)
					hiBin = inf
				endif
				spSum_IntWave[] = (tempW[p] >= loBin && tempW[p] < hiBin) ? 1 : 0
				inBin = sum(spSum_IntWave)
				// is there anything to calculate?
				if(inBin == 0)
					continue
				endif
				// yes, then 
				FindValue/I=1 spSum_IntWave
				if(V_row == -1)
					continue
				else
					firstRow = V_row
				endif
				spSum_nWave[] = (spSum_IntWave[p] == 1) ? p - firstRow : NaN
				if(mod(inBin,2) == 0)
					// change the foundRowValue to a triangular number (divisor would be inBin - 1 to get -1 to +1)
					spSum_nWave[] = (mod(spSum_nWave[p],2) == 0) ? (spSum_nWave[p] + 1) / -(maxNBin - 1) : spSum_nWave[p] / (maxNBin - 1)
				else
					// change the foundRowValue to a triangular number (divisor would be inBin to get -1 to +1)
					spSum_nWave[] = (mod(spSum_nWave[p],2) == 0) ? spSum_nWave[p] / maxNBin : (spSum_nWave[p] + 1) / -maxNBin
				endif
				// assign to xWave
				spSum_xWave[] = (numtype(spSum_nWave[p]) != 2) ? i + spSum_nWave[p] * groupWidth : spSum_xWave[p]
			endfor
			// make the order of xWave match sum_Speed_*
			Sort keyW, spSum_xWave
			// deduce which rows of sum_Speed_* come from which expt
			wList = WaveList("cd_" + condName + "*", ";", "")
			nTracks = ItemsInList(wList)
			if(nTracks != numpnts(w))
				DoAlert 0, "Check how the split data has compiled into the master wave"
			endif
			speedName = "sum_Index_" + condName
			Make/O/N=(nTracks) $speedName
			Wave indexW = $speedName
			for(j = 0; j < nTracks; j += 1)
				wName = StringFromList(j,wList)
				wName = ReplaceString("cd_"+condName+"_",wName,"") // delete first bit
				indexW[j] = str2num(wName[0]) - 1 // this gives the index (0-Based!)
			endfor
			// check that max here is the same as reps
			if(WaveMax(indexW) + 1 != reps)
				DoAlert 0, "Problem: please check how the split waves got reassembled"
			endif
			aveName = "spSum_" + condname + "_Ave"
			Make/O/N=(reps,4) $aveName
			Wave w1 = $aveName
			errName = ReplaceString("_Ave",AveName,"_Err")
			Make/O/N=(reps) $errName
			Wave w2 = $errName
			// set 1st column to be the x position for the averages
			w1[][0] = i
			// y values go in 2nd col and in 3rd col we put the marker types, 4th will be p
			Make/O/N=(12)/FREE markerW={19,17,16,18,23,29,26,14,8,6,5,7}
			w1[][2] = markerW[p]
			w1[][3] = p
			for(j = 0; j < reps; j += 1)
				Extract/O/FREE w, extractedValW, indexW == j
				WaveStats extractedValW
				w1[j][1] = V_Avg
				w2[j] = V_sem
			endfor
			// put the means for each repeat for this group into collatedMat (to do stats)
			collatedMat[][i] = w1[p][1]
			wName = "sum_Speed_" + condName
			// add to first superplot
			AppendToGraph/W=SuperPlot_cond $wName vs spSum_xWave
			ModifyGraph/W=SuperPlot_cond mode($wName)=3,marker($wName)=19
			ModifyGraph/W=SuperPlot_cond rgb($wName)=(colorWave[i][0],colorWave[i][1],colorWave[i][2],alphaLevel)
			AppendToGraph/W=SuperPlot_cond w1[][1] vs w1[][0]
			ModifyGraph/W=SuperPlot_cond rgb($aveName)=(0,0,0)
			ModifyGraph/W=SuperPlot_cond mode($aveName)=3
			ModifyGraph/W=SuperPlot_cond zmrkNum($aveName)={w1[][2]}
			// error bars can be added here if required
//			ErrorBars/W=SuperPlot_cond $aveName Y,wave=(w2,w2)

			// add to other superplot
			AppendToGraph/W=SuperPlot_rep $wName vs spSum_xWave
			ModifyGraph/W=SuperPlot_rep mode($wName)=3,marker($wName)=19
			ModifyGraph/W=SuperPlot_rep zColor($wName)={indexW,0,reps,cindexRGB,0,colorSplitWaveA}
			AppendToGraph/W=SuperPlot_rep w1[][1] vs w1[][0]
			ModifyGraph/W=SuperPlot_rep zColor($aveName)={w1[][3],0,reps,cindexRGB,0,colorSplitWave}
			ModifyGraph/W=SuperPlot_rep mode($aveName)=3,marker($aveName)=19,useMrkStrokeRGB($aveName)=1
			SetDataFolder root:
		endfor
		Label/W=SuperPlot_cond left "Average speed ("+unitWave[2]+")"
		SetAxis/A/N=1/E=1/W=SuperPlot_cond left
		Make/O/N=(numpnts(labelWave)) labelXWave = p
		ModifyGraph/W=SuperPlot_cond userticks(bottom)={labelXWave,labelWave}
		SetAxis/W=SuperPlot_cond bottom WaveMin(labelXWave) - 0.5, WaveMax(labelXWave) + 0.5

		Label/W=SuperPlot_rep left "Average speed ("+unitWave[2]+")"
		SetAxis/A/N=1/E=1/W=SuperPlot_rep left
		ModifyGraph/W=SuperPlot_rep userticks(bottom)={labelXWave,labelWave}
		SetAxis/W=SuperPlot_rep bottom WaveMin(labelXWave) - 0.5, WaveMax(labelXWave) + 0.5
		// do stats
		DoStatsAndLabel(collatedMat,"SuperPlot_rep")
		// add superplots to layout
		AppendLayoutObject /W=summaryLayout graph SuperPlot_cond
		AppendLayoutObject /W=summaryLayout graph SuperPlot_rep
	endif
	
	// finish up by going to root and making sure layout is OK
	SetDataFolder root:
	// Tidy summary layout
	DoWindow/F summaryLayout
	// in case these are not captured as prefs
	LayoutPageAction size(-1)=(595, 842), margins(-1)=(18, 18, 18, 18)
	ModifyLayout units=0
	ModifyLayout frame=0,trans=1
	Execute /Q "Tile/A=(4,3)/O=1"
End

///	@param	w1	wave for calculation
///	@param	segmentLength	variable passed for speed, rather than looking up
STATIC Function StravaCalc(w1,segmentLength)
	Wave w1
	Variable segmentLength
	Variable nPnts = numpnts(w1)
	Variable maxDist = w1[nPnts-1]
	Variable returnVar = 1000
	Variable i
	
	for(i = 0 ; i < nPnts; i += 1)
		if(w1[i] + segmentLength > maxDist)
			break
		endif
		FindLevel/Q/r=[i] w1, w1[i] + segmentLength
		if(V_flag == 1)
			break
		endif
		returnVar = min(returnVar,V_LevelX)
	endfor
	
	if(returnVar == 1000)
		returnVar = NaN
	endif	
	return returnVar
End

STATIC Function DoStatsAndLabel(m0,plotName)
	Wave m0
	String plotName
	
	String wName = NameOfWave(m0)
	Variable groups = DimSize(m0,1)
	Variable reps = DimSize(m0,0)
	if(reps < 3)
		Print "Less than three repeats, so no stats added to superplot"
		return -1
	endif
	String pStr, boxName, lookup
	Variable pVal, i
	if(groups == 2)
		Make/O/N=(reps)/FREE w0,w1
		w0[] = m0[p][0]
		w1[] = m0[p][1]
		KillWaves/Z m0
		StatsTTest/Q w0,w1
		Wave/Z W_StatsTTest
		pVal = W_StatsTTest[%P]
		pStr = FormatPValue(pVal)
		TextBox/C/N=text0/W=$plotName/F=0/A=MT/X=0.00/Y=0.00 "p = " + pStr
	elseif(groups > 2)
		SplitWave m0
		StatsDunnettTest/Q/WSTR=S_WaveNames
		WAVE/Z M_DunnettTestResults
		for(i = 1; i < groups; i += 1)
			boxName = "text" + num2str(i)
			lookup = "0_vs_" + num2str(i)
			pStr = FormatPValue(M_DunnettTestResults[%$(lookup)][%P])
			TextBox/C/N=$boxName/W=$plotName/F=0/A=MT/X=(((i - (groups/2 - 0.5))/(groups / 2))/2 * 100)/Y=0.00 pStr
		endfor
		KillTheseWaves(S_WaveNames)
	else
		return -1
	endif
end

STATIC Function/S FormatPValue(pValVar)
	Variable pValVar
	
	String pVal = ""
	String preStr,postStr
	
	if(pValVar > 0.05)
		sprintf pVal, "%*.*f", 2,2, pValVar
	else
		sprintf pVal, "%*.*e", 1,1, pValVar
	endif
	if(pValVar > 0.99)
		// replace any p ~= 1 with p > 0.99
		pVal = "> 0.99"
	elseif(pValVar == 0)
		// replace any p = 0 with p < 1e-24
		pVal = "< 1e-24"
	endif
	if(StringMatch(pVal,"*e*") == 1)
		preStr = pVal[0,2]
		if(StringMatch(pVal[5],"0") == 1)
			postStr = pVal[6]
		else
			postStr = pVal[5,6]
		endif
		pVal = preStr + " x 10\S\u2212" + postStr
	endif
	return pVal
End

// Saving csv output from Manual Tracking in FIJI is missing the first column
// It can also not be read by Manual Tracking because it is comma-separated and not tab-separated
Function Excel2CSV()
	SetDataFolder root:
	NewDataFolder/O/S root:convert
	
	XLLoadWave/J=1
	NewPath/O/Q path1, S_path
	Variable moviemax = ItemsInList(S_value)
	String sheet,csvFileName,prefix,wList,newName
	
	Variable i
	
	for(i = 0; i < moviemax; i += 1)
		sheet = StringFromList(i,S_Value)
		csvFileName = S_filename + "_" + sheet + ".csv"
		prefix = "tempW_" + num2str(i)
		XLLoadWave/S=sheet/R=(A1,H2000)/COLT="N"/O/K=0/N=$prefix/P=path1/Q S_fileName
		wList = wavelist(prefix + "*",";","")	//make matrices
		newName = "tempM_" + num2str(i)
		Concatenate/O/KILL wList, $newName
		Wave m0 = $newName
		CheckColumnsOfMatrix(m0)
		SetDimLabel 1,0,index,m0
		SetDimLabel 1,1,TrackNo,m0
		SetDimLabel 1,2,SliceNo,m0
		SetDimLabel 1,3,x,m0
		SetDimLabel 1,4,y,m0
		SetDimLabel 1,5,distance,m0
		SetDimLabel 1,6,velocity,m0
		SetDimLabel 1,7,pixelvalue,m0
		Save/J/M="\n"/U={0,0,1,0}/O/P=path1 m0 as csvFileName
		KillWaves/Z m0
	endfor
	SetDataFolder root:
	KillDataFolder/Z root:convert
End

Function CSV2CSV()
	SetDataFolder root:
	NewDataFolder/O/S root:convert
	
	NewPath/O/Q/M="Select directory of original CSVs" ExpDiskFolder
	NewPath/O/Q/M="Choose destination directory for converted CSVs" outputDiskFolder
	String fileList = IndexedFile(expDiskFolder,-1,".csv")
	Variable moviemax = ItemsInList(fileList)
	String sheet,csvFileName,prefix,newName,wList
	
	Variable i
	
	for(i = 0; i < moviemax; i += 1)
		sheet = StringFromList(i, fileList)
		prefix = "tempW_" + num2str(i)
		LoadWave/A=$prefix/J/K=1/L={0,1,0,0,0}/O/P=expDiskFolder/Q sheet
		wList = wavelist(prefix + "*",";","")	// make matrix for each sheet
		newName = "tempM_" + num2str(i)
		Concatenate/O/KILL wList, $newName
		Wave m0 = $newName
		CheckColumnsOfMatrix(m0)
		SetDimLabel 1,0,index,m0
		SetDimLabel 1,1,TrackNo,m0
		SetDimLabel 1,2,SliceNo,m0
		SetDimLabel 1,3,x,m0
		SetDimLabel 1,4,y,m0
		SetDimLabel 1,5,distance,m0
		SetDimLabel 1,6,velocity,m0
		SetDimLabel 1,7,pixelvalue,m0
		Save/J/M="\n"/U={0,0,1,0}/O/P=outputDiskFolder m0 as sheet
		KillWaves/Z m0
	endfor
	SetDataFolder root:
	KillDataFolder/Z root:convert
End


////////////////////////////////////////////////////////////////////////
// Panel functions
///////////////////////////////////////////////////////////////////////

Function SetUp_Panel(optVar)
	Variable optVar
	
	// suggested values
	Variable cond = 2
	Variable reps = 0
	if(optVar == 1)
		reps = 4
	endif
	Variable tStep = 20
	Variable pxSize = 0.22698
	Variable segmentLength = 25
	Variable minPoints = 6
	// add parameters to wave - note that if optVar == 0, reps is added as 0 so that we can determine that we are not superplotting
	Make/O/D/N=6 paramWave = {cond,tStep,pxSize,segmentLength,reps,minPoints}
	
	String panelName = "su_panel"
	KillWindow/Z $panelName
	NewPanel/N=$panelName/K=1/W=(40,40,540,380) as "Prepare for analysis"
	DefaultGUIFont/W=$panelName/Mac popup={"_IgorSmall",0,0}
	// controls
	String titleString = "Specify parameters for CellMigration"
	if(optVar == 1)
		titleString = "Specify parameters for CellMigration Superplot"
	endif
	TitleBox tb0,pos={20,20},size={115,20},title=titleString,fstyle=1,fsize=11,labelBack=(55000,55000,65000),frame=0

	SetVariable setvar0,pos={20,60},size={220,16},title="How many conditions?",fSize=10,limits={1,inf,1},value=paramWave[0]
	if(optVar == 1)
		SetVariable setvar4,pos={250,60},size={220,16},title="How many repeats per condition?",fSize=10,limits={1,inf,1},value=paramWave[4]
	endif
	SetVariable setvar1,pos={20,100},size={220,16},title="Time interval",fSize=10,limits={0.001,999,0},value=paramWave[1]
	SetVariable setvar2,pos={20,140},size={220,16},title="Pixel size",fSize=10,limits={0.0001,999,0},value=paramWave[2]
	SetVariable setvar3,pos={20,180},size={220,16},title="Segment length",fSize=10,limits={0.0001,999,0},value=paramWave[3]
	SetVariable setvar5,pos={20,220},size={220,16},title="Minimum number of points per track",fSize=10,limits={4,100,1},value=paramWave[5]
	
	// define units
	String timeList = "h;min;s;ms;"
	String puTime = "\""+timeList+"\""
	String presetTime = StringFromList(1,timeList)
	Variable timeMode = 1 + WhichListItem(presetTime,timeList) // complicated
	PopUpMenu pu0,pos={250,100},size={90,14}, bodywidth=90,value= #puTime, popvalue = presetTime, mode=timeMode, proc=unitPopupHelper
	String distList = "m;mm;\u03BCm;nm;"
	String puDist = "\""+distList+"\""
	String presetDist = StringFromList(2,distList)
	Variable distMode = 1 + WhichListItem(presetDist,distList) // complicated
	PopUpMenu pu1,pos={250,140},size={90,14}, bodywidth=90,value= #puDist, popvalue = presetDist, mode=distMode, proc=unitPopupHelper
	// we need a unitwave to store units
	Make/O/N=3/T unitWave = {presetTime,presetDist,presetDist+"/"+presetTime}
	// display speed
	SetVariable noEdit,pos={272,260},size={208,16},title="Speed will be displayed as",fSize=11,value=unitWave[2],disable=2
	// display units for segment length
	SetVariable noEdit2,pos={250,180},size={40,16},title=" ",fSize=11,value=unitWave[1],disable=2
	
	// the buttons
	Button Cancel,pos={260,300},size={100,20},proc=SUButtonProc,title="Cancel"
	Button Next,pos={380,300},size={100,20},proc=SUButtonProc,title="Next"
End

Function unitPopupHelper(s) : PopupMenuControl
	STRUCT WMPopupAction &s

	switch (s.eventCode)
		case 2: // mouse up
			String name = s.ctrlName
			Variable rownum = str2num(name[2,inf])  // assumes the format to be pux where x is the row
			Variable sel = s.popNum-1	// 1-6 (popup) vs. 0-5 (wave)
			String popStr = s.popStr
		
			WAVE/Z/T unitWave
			unitWave[rowNum] = popStr
			unitWave[2] = unitWave[1]+"/"+unitWave[0]
			break
		case -1:
			break
	endswitch
	
	return 0
End


Function SUButtonProc(ba) : ButtonControl
	STRUCT WMButtonAction &ba
	
	switch(ba.eventCode)
		case 2 :
			if(CmpStr(ba.ctrlName,"Next") == 0)
				KillWindow/Z $(ba.win)
				ProceedToMigrate()
				return 0
			else
				KillWindow/Z $(ba.win)
				return -1
			endif
		case -1:
			break
	endswitch
	
	return 0
End


///	@param	cond	number of conditions - determines size of box
Function myIO_Panel(cond)
	Variable cond
	
	Wave/Z colorWave = root:colorWave
	// make global text wave to store paths
	Make/T/O/N=(cond) condWave
	Make/T/O/N=(cond) PathWave1,PathWave2
	DoWindow/K FilePicker
	NewPanel/N=FilePicker/K=1/W=(40,40,840,150+30*cond)
	// labelling of columns
	DrawText/W=FilePicker 10,30,"Name"
	DrawText/W=FilePicker 160,30,"Cell tracking data (directory of CSVs or Excel file)"
	DrawText/W=FilePicker 480,30,"Optional: stationary data"
	DrawText/W=FilePicker 10,100+30*cond,"CellMigration"
	// do it button
	Button DoIt,pos={680,70+30*cond},size={100,20},proc=DoItButtonProc,title="Do It"
	// insert rows
	String buttonName1a,buttonName1b,buttonName2a,buttonName2b,boxName0,boxName1,boxName2
	Variable i
	
	for(i = 0; i < cond; i += 1)
		boxName0 = "box0_" + num2str(i)
		buttonName1a = "dir1_" + num2str(i)
		buttonName1b = "file1_" + num2str(i)
		boxName1 = "box1_" + num2str(i)
		buttonName2a = "dir2_" + num2str(i)
		buttonName2b = "file2_" + num2str(i)
		boxName2 = "box2_" + num2str(i)
		// row label
		DrawText/W=FilePicker 10,68+i*30,num2str(i+1)
		// condition label
		SetVariable $boxName0,pos={30,53+i*30},size={100,14},value= condWave[i], title=" "
		// dir button
		Button $buttonName1a,pos={160,50+i*30},size={38,20},proc=ButtonProc,title="Dir"
		// file button
		Button $buttonName1b,pos={200,50+i*30},size={38,20},proc=ButtonProc,title="File"
		// file or dir box
		SetVariable $boxName1,pos={240,53+i*30},size={220,14},value= PathWave1[i], title=" "
		// stationary dir button
		Button $buttonName2a,pos={480,50+i*30},size={38,20},proc=ButtonProc,title="Dir"
		// stationary button
		Button $buttonName2b,pos={520,50+i*30},size={38,20},proc=ButtonProc,title="File"
		// stationary or dir box
		SetVariable $boxName2,pos={560,53+i*30},size={220,14},value= PathWave2[i], title=" "
		SetDrawEnv fillfgc=(colorWave[i][0],colorWave[i][1],colorWave[i][2])
		DrawOval/W=FilePicker 130,50+i*30,148,68+i*30
	endfor
End

// define buttons
Function ButtonProc(ctrlName) : ButtonControl
	String ctrlName

	Wave/T PathWave1,PathWave2
	Variable refnum, wNum, ii
	String expr, wNumStr, iiStr, stringForTextWave

	if(StringMatch(ctrlName,"file*") == 1)
		expr="file([[:digit:]]+)\\w([[:digit:]]+)"
		SplitString/E=(expr) ctrlName, wNumStr, iiStr
		// get File Path
		Open/D/R/F="*.xls*"/M="Select Excel Workbook" refNum
		stringForTextWave = S_filename
	else
		expr="dir([[:digit:]]+)\\w([[:digit:]]+)"
		SplitString/E=(expr) ctrlName, wNumStr, iiStr
		// set outputfolder
		NewPath/O/Q DirOfCSVs
		PathInfo DirOfCSVs
		stringForTextWave = S_Path
	endif

	if (strlen(stringForTextWave) == 0) // user pressed cancel
		return -1
	endif
	wNum = str2num(wNumStr)
	ii = str2num(iiStr)
	if (wNum == 1)
		PathWave1[ii] = stringForTextWave
	else
		PathWave2[ii] = stringForTextWave
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
				DoAlert 0, "Error: Not all conditions have a name."
				break
			endif
			okvar = NameChecker(CondWave)
			if (okvar == -1)
				DoAlert 0, "Error: Two conditions have the same name."
				break
			endif
			okvar = WaveChecker(PathWave1)
			if (okvar == -1)
				DoAlert 0, "Error: Not all conditions have a file to load."
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

STATIC function NameChecker(TextWaveToCheck)
	Wave/T TextWaveToCheck
	Variable nRows = numpnts(TextWaveToCheck)
	Variable len
	
	Variable i,j
	
	for(i = 0; i < nRows; i += 1)
		for(j = 0; j < nRows; j += 1)
			if(j > i)
				if(cmpstr(TextWaveToCheck[i], TextWaveToCheck[j], 0) == 0)
					return -1
				endif
			endif
		endfor
	endfor
	return 1
End

///	@param	cond	number of conditions - determines size of box
///	@param	reps	number of repitions - determines size of box
Function Superplot_Panel(cond, reps)
	Variable cond, reps
	
	Variable allCond = cond * reps
	Wave/Z colorWave = root:colorWave
	// make global text wave to store paths
	Make/T/O/N=(cond) condWave // store conditions
	Make/T/O/N=(allCond) condSplitWave // store conditions subdivided
	Make/T/O/N=(allCond) PathWave1,PathWave2
	DoWindow/K FilePicker
	NewPanel/N=FilePicker/K=1/W=(40,40,840,150+30*allCond)
	// labelling of columns
	DrawText/W=FilePicker 10,30,"Name"
	DrawText/W=FilePicker 160,30,"Cell tracking data (directory of CSVs or Excel file)"
	DrawText/W=FilePicker 480,30,"Optional: stationary data"
	DrawText/W=FilePicker 10,100+30*allCond,"CellMigration"
	// do it button
	Button DoIt,pos={680,70+30*allCond},size={100,20},proc=SPDoItButtonProc,title="Do It"
	// insert rows
	String buttonName1a,buttonName1b,buttonName2a,buttonName2b,boxName0,boxName1,boxName2
	Variable i
	
	for(i = 0; i < allCond; i += 1)
		boxName0 = "box0_" + num2str(i)
		buttonName1a = "dir1_" + num2str(i)
		buttonName1b = "file1_" + num2str(i)
		boxName1 = "box1_" + num2str(i)
		buttonName2a = "dir2_" + num2str(i)
		buttonName2b = "file2_" + num2str(i)
		boxName2 = "box2_" + num2str(i)
		// row label
		DrawText/W=FilePicker 10,68+i*30,num2str(mod(i,reps)+1)
		// condition label
		SetVariable $boxName0,pos={30,53+i*30},size={100,14},value= condWave[floor(i/reps)], title=" "
		// dir button
		Button $buttonName1a,pos={160,50+i*30},size={38,20},proc=ButtonProc,title="Dir"
		// file button
		Button $buttonName1b,pos={200,50+i*30},size={38,20},proc=ButtonProc,title="File"
		// file or dir box
		SetVariable $boxName1,pos={240,53+i*30},size={220,14},value= PathWave1[i], title=" "
		// stationary dir button
		Button $buttonName2a,pos={480,50+i*30},size={38,20},proc=ButtonProc,title="Dir"
		// stationary button
		Button $buttonName2b,pos={520,50+i*30},size={38,20},proc=ButtonProc,title="File"
		// stationary or dir box
		SetVariable $boxName2,pos={560,53+i*30},size={220,14},value= PathWave2[i], title=" "
		SetDrawEnv fillfgc=(colorWave[floor(i/reps)][0],colorWave[floor(i/reps)][1],colorWave[floor(i/reps)][2])
		DrawOval/W=FilePicker 130,50+i*30,148,68+i*30
	endfor
End


Function SPDoItButtonProc(ctrlName) : ButtonControl
	String ctrlName
 	
 	WAVE/T CondWave, condSplitWave, PathWave1
	Variable okvar = 0
	
	strswitch(ctrlName)	
		case "DoIt" :
			// check MasterCondWave
			okvar = WaveChecker(CondWave)
			if (okvar == -1)
				DoAlert 0, "Not all conditions have a name."
				break
			endif
			okvar = NameChecker(CondWave)
			if (okvar == -1)
				DoAlert 0, "Error: Two conditions have the same name."
				break
			endif
			okvar = WaveChecker(PathWave1)
			if (okvar == -1)
				DoAlert 0, "Error: Not all conditions have a file to load."
				break
			else
				Variable reps = numpnts(CondSplitWave) / numpnts(CondWave)
				CondSplitWave[] = CondWave[floor(p / reps)] + "_" + num2str(mod(p,reps) + 1)
				Migrate()
			endif
	endswitch	
End

////////////////////////////////////////////////////////////////////////
// Utility functions
////////////////////////////////////////////////////////////////////////
// Colours are taken from Paul Tol SRON stylesheet
// Colours updated. Brighter palette for up to 6 colours, then palette of 12 for > 6
// Define colours
StrConstant SRON_1 = "0x4477aa;"
StrConstant SRON_2 = "0x4477aa;0xee6677;"
StrConstant SRON_3 = "0x4477aa;0xccbb44;0xee6677;"
StrConstant SRON_4 = "0x4477aa;0x228833;0xccbb44;0xee6677;"
StrConstant SRON_5 = "0x4477aa;0x66ccee;0x228833;0xccbb44;0xee6677;"
StrConstant SRON_6 = "0x4477aa;0x66ccee;0x228833;0xccbb44;0xee6677;0xaa3377;"
StrConstant SRON_7 = "0x332288;0x88ccee;0x44aa99;0x117733;0xddcc77;0xcc6677;0xaa4499;"
StrConstant SRON_8 = "0x332288;0x88ccee;0x44aa99;0x117733;0x999933;0xddcc77;0xcc6677;0xaa4499;"
StrConstant SRON_9 = "0x332288;0x88ccee;0x44aa99;0x117733;0x999933;0xddcc77;0xcc6677;0x882255;0xaa4499;"
StrConstant SRON_10 = "0x332288;0x88ccee;0x44aa99;0x117733;0x999933;0xddcc77;0x661100;0xcc6677;0x882255;0xaa4499;"
StrConstant SRON_11 = "0x332288;0x6699cc;0x88ccee;0x44aa99;0x117733;0x999933;0xddcc77;0x661100;0xcc6677;0x882255;0xaa4499;"
StrConstant SRON_12 = "0x332288;0x6699cc;0x88ccee;0x44aa99;0x117733;0x999933;0xddcc77;0x661100;0xcc6677;0xaa4466;0x882255;0xaa4499;"

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
STATIC Function byte_value(data, byte)
	Variable data
	Variable byte
	return (data & (0xFF * (2^(8*byte)))) / (2^(8*byte))
End

/// @param	cond	variable for number of conditions
Function MakeColorWave(nRow, wName, [alpha])
	Variable nRow
	String wName
	Variable alpha
	
	// Pick colours from SRON palettes
	String pal
	if(nRow == 1)
		pal = SRON_1
	elseif(nRow == 2)
		pal = SRON_2
	elseif(nRow == 3)
		pal = SRON_3
	elseif(nRow == 4)
		pal = SRON_4
	elseif(nRow == 5)
		pal = SRON_5
	elseif(nRow == 6)
		pal = SRON_6
	elseif(nRow == 7)
		pal = SRON_7
	elseif(nRow == 8)
		pal = SRON_8
	elseif(nRow == 9)
		pal = SRON_9
	elseif(nRow == 10)
		pal = SRON_10
	elseif(nRow == 11)
		pal = SRON_11
	else
		pal = SRON_12
	endif
	
	Variable color
	String colorWaveFullName = "root:" + wName
	if(ParamisDefault(alpha) == 1)
		Make/O/N=(nRow,3) $colorWaveFullName
		WAVE w = $colorWaveFullName
	else
		Make/O/N=(nRow,4) $colorWaveFullName
		WAVE w = $colorWaveFullName
		w[][3] = alpha
	endif
	
	Variable i
	
	for(i = 0; i < nRow; i += 1)
		// specify colours
		color = str2num(StringFromList(mod(i, 12),pal))
		w[i][0] = hexcolor_red(color)
		w[i][1] = hexcolor_green(color)
		w[i][2] = hexcolor_blue(color)
	endfor
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

STATIC Function KillTheseWaves(wList)
	String wList
	Variable allItems = ItemsInList(wList)
	String name
	Variable i
 
	for(i = 0; i < allItems; i += 1)
		name = StringFromList(i, wList)
		KillWaves/Z $name
	endfor
End

Function/WAVE CleanUpCondWave(condWave)
	WAVE/T condWave
	Duplicate/O condWave, root:labelWave
	condWave[] = CleanupName(condWave[p],0)
	
	return root:labelWave
End

STATIC Function LoadNiceCTableW()
	NewDataFolder/O root:Packages
	NewDataFolder/O root:Packages:ColorTables
	String/G root:Packages:ColorTables:oldDF = GetDataFolder(1)
	NewDataFolder/O/S root:Packages:ColorTables:Moreland
	LoadWave/H/O/P=Igor ":Color Tables:Moreland:SmoothCoolWarm256.ibw"
	KillStrings/Z/A
	SetDataFolder root:
	KillStrings/Z root:Packages:ColorTables:oldDF
	KillVariables/Z root:Packages:ColorTables:Moreland:V_flag
End

Function TidyCondSpecificLayouts()
	WAVE/T condWave = root:condWave
	String layoutName,condName,boxName
	Variable cond = numpnts(condWave)
	Variable pgMax = 2
	Variable i,j
	
	for(i = 0; i < cond; i += 1)
		condName = condWave[i]
		layoutName = condName + "_layout"
		DoWindow/F $layoutName
		for(j = 1; j < pgMax + 1; j += 1)
			LayoutPageAction/W=$layoutName page=(j)
			LayoutPageAction/W=$layoutName size(-1)=(595, 842), margins(-1)=(18, 18, 18, 18)
			ModifyLayout/W=$layoutName units=0
			ModifyLayout/W=$layoutName frame=0,trans=1
			if(j == 1)
				Execute /Q "Tile"
			endif
			boxName = "text" + num2str(j)
			TextBox/W=$layoutName/C/N=$boxName/F=0/A=RB/X=0.00/Y=0.00 condName
		endfor
		LayoutPageAction/W=$layoutName page=(1)
	endfor
	DoUpdate
End

Function SaveAllReports()
	DoUpdate
	String layoutList = WinList("*layout", ";", "WIN:4")
	Variable nLayouts = ItemsInList(layoutList)
	if(nLayouts == 0)
		DoAlert 0, "No reports to save!"
		return -1
	endif
	
	NewPath/O/Q OutputPath
	String layoutName,fileName
	Variable pgMax = 2
	Variable i,j
	
	for(i = 0; i < nLayouts; i += 1)
		layoutName = StringFromList(i,layoutList)
		pgMax = 2
		// export graphs as PDF (EMF on Windows)
		if(defined(WINDOWS) == 1)
			if(CmpStr(layoutName, "summaryLayout") == 0)
				pgMax = 1
			endif
			// save all pages in a loop
			for(j = 1; j < pgMax +1 ; j += 1)
				fileName = layoutName + num2str(j) + ".emf"
				SavePICT/E=-2/P=OutputPath/WIN=$layoutName/W=(0,0,0,0)/PGR=(j,-1) as fileName
			endfor
		else
			fileName = layoutName + ".pdf"
			SavePICT/E=-2/P=OutputPath/WIN=$layoutName/W=(0,0,0,0)/PGR=(1,-1) as fileName
		endif
	endfor
End

Function RecolorAllPlotsWrapper()
	SetDataFolder root:
	WAVE/Z colorWave = root:colorWave
	if(!WaveExists(colorWave))
		DoAlert 0, "3-column colorwave required"
		return -1
	endif
	Duplicate/O colorWave, colorWave_BKP
	// present dialog to work on recoloring
	CWE_MakeClientColorEditor(colorWave, 0, 65535, "Edit Colors","ColorWave","RecolorAllPlots")
End

Function RecolorAllPlots(colorWave,colorSpace)
	Wave colorWave
	Variable colorSpace
	WAVE/T condWave = root:condWave
	Variable cond = numpnts(condWave)

	Variable i,j,k
	
	String plotList = "anglePlot;cdPlot;DAplot;dDplot;ivHist;ivPlot;MSDplot;quilt;sprkln;tkplot;"
	// plots with less than 1 alpha
	String halfList = "cdPlot;DAplot;dDplot;ivPlot;MSDplot;tkPlot;"
	plotList = RemoveFromList(halfList, plotList)
	Variable nPlots = ItemsInList(plotList)
	String condName,plotName,traceList,traceName
	Variable nTraces
	
	for(i = 0; i < cond; i += 1)
		condName = condWave[i]
		for(j = 0; j < nPlots; j += 1)
			plotName = condName + "_" + StringFromList(j,plotList)
			traceList = TraceNameList(plotName, ";", 1)
			nTraces = ItemsInList(traceList)
			for(k = 0; k < nTraces; k += 1)
				traceName = StringFromList(k,traceList)
				if(stringmatch(traceName,"W_*") == 0)
					ModifyGraph/W=$plotName rgb($traceName)=(colorWave[i][0],colorWave[i][1],colorWave[i][2])
				endif
			endfor
		endfor
	endfor
	
	// now recolor traces with 0.5 alpha
	plotList = halfList
	nPlots = ItemsInList(plotList)
	
	for(i = 0; i < cond; i += 1)
		condName = condWave[i]
		for(j = 0; j < nPlots; j += 1)
			plotName = condName + "_" + StringFromList(j,plotList)
			traceList = TraceNameList(plotName, ";", 1)
			nTraces = ItemsInList(traceList)
			for(k = 0; k < nTraces; k += 1)
				traceName = StringFromList(k,traceList)
				if(stringmatch(traceName,"W_*") == 0)
					ModifyGraph/W=$plotName rgb($traceName)=(colorWave[i][0],colorWave[i][1],colorWave[i][2],32768)
				endif
			endfor
		endfor
	endfor
	
	plotlist = "angleHPlot;cdPlot;DAPlot;dDplot;ivHPlot;ivPlot;MSDPlot;"
	nPlots = ItemsInList(plotList)
	
	for(i = 0; i < nPlots; i += 1)
		plotName = StringFromList(i,plotList)
		traceList = TraceNameList(plotName, ";", 1)
		nTraces = ItemsInList(traceList)
		for(j = 0; j < nTraces; j += 1)
			traceName = StringFromList(j,traceList)
			for(k = 0; k < cond; k += 1)
				condName = condWave[k]
				if(stringmatch(traceName,"*"+condName) == 1)
					ModifyGraph/W=$plotName rgb($traceName)=(colorWave[k][0],colorWave[k][1],colorWave[k][2])
				endif
			endfor
		endfor
	endfor
	
	plotlist = "speedPlot;stravaPlot;SuperPlot_cond;"
	nPlots = ItemsInList(plotList)
	Variable alphaLevel
	
	for(i = 0; i < nPlots; i += 1)
		plotName = StringFromList(i,plotList)
		traceList = TraceNameList(plotName, ";", 25)
		nTraces = ItemsInList(traceList)
		for(j = 0; j < nTraces; j += 1)
			traceName = StringFromList(j,traceList)
			Wave w = TraceNameToWaveRef(plotName,traceName)
			alphaLevel = DecideOpacity(DimSize(w,0))
			for(k = 0; k < cond; k += 1)
				condName = condWave[k]
				if(stringmatch(traceName,"*"+condName) == 1)
					ModifyGraph/W=$plotName rgb($traceName)=(colorWave[k][0],colorWave[k][1],colorWave[k][2], alphaLevel)
				endif
			endfor
		endfor
	endfor
End

Function RerunAnalysis()
	SetDataFolder root:
	String fullList = WinList("*", ";","WIN:7")
	Variable allItems = ItemsInList(fullList)
	String name
	Variable i
 
	for(i = 0; i < allItems; i += 1)
		name = StringFromList(i, fullList)
		KillWindow/Z $name		
	endfor

	KillDataFolder root:data:
	WAVE/Z/T CondWave
	if(!WaveExists(CondWave))
		DoAlert 0, "Something is wrong. Cannot rerun the analysis."
		return -1
	endif
	Migrate()
End

Function AboutCellMigr()
	String vStr = "CellMigration\rVersion " + num2str(GetProcedureVersion("CellMigration.ipf"))
	DoAlert 0, vStr
End

// Function from aclight to retrieve #pragma version number
/// @param procedureWinTitleStr	This is the name of this procedure window
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

STATIC Function DecideOpacity(nTrace)
	Variable nTrace
	Variable alpha
	if(nTrace < 10)
		alpha = 1
	elseif(nTrace < 50)
		alpha = 0.5
	elseif(nTrace < 100)
		alpha = 0.3
	else
		alpha = 0.2
	endif
	alpha = round(65535 * alpha)
	return alpha
End

// This function will make a "multicolumn" boxplot or violinplot (Igor >8 only) 
///	@param	matA	matrix of points to be appended
///	@param	plotName	string to tell igor which graph window to work on
///	@param	ii	variable to indicate which condition (for coloring)
STATIC Function BuildBoxOrViolinPlot(matA,plotName,ii)
	WAVE matA
	String plotName
	Variable ii
	
	String wName = NameOfWave(matA)
	Wave/T/Z condWave = root:condWave
	Wave/Z colorWave = root:colorWave
	//  This works because all matrices passed to this function have the same dimensions
	Variable nTracks = DimSize(matA,0)
	if(nTracks < 100)
		AppendBoxPlot/W=$plotName matA vs condWave
		ModifyBoxPlot/W=$plotName trace=$wName,markers={19,-1,19},markerSizes={2,2,2}
		ModifyBoxPlot/W=$plotName trace=$wName,whiskerMethod=4
	else
		AppendViolinPlot/W=$plotName matA vs condWave
		ModifyViolinPlot/W=$plotName trace=$wName,ShowMean,MeanMarker=19,CloseOutline
		ModifyViolinPlot/W=$plotName trace=$wName,DataMarker=19
	endif
	Variable alphaLevel = DecideOpacity(nTracks)
	ModifyGraph/W=$plotName rgb($wName)=(colorWave[ii][0],colorWave[ii][1],colorWave[ii][2],alphaLevel)
End

STATIC Function CheckStravaW(w)
	Wave w
	Duplicate/FREE w, tempW
	WaveTransform zapnans tempW
	if(numpnts(tempW) == 0)
		return 0
	else
		return 1
	endif
End

STATIC Function WorkOutSpacing(px)
	Variable px
	Variable spacing
	if (px < 1)
		spacing = 10^floor(log(200 * px))
	else
		spacing = 10^ceil(log(200 * px))
	endif
	
	return spacing
End

// not currently used
///	@param	matA	2d wave of xy coords offset to origin
STATIC Function DistanceFinder(matA)
	Wave MatA
	MatrixOp/O/FREE tempNorm = sqrt(sumRows(matA * matA))
	return WaveMax(tempNorm)
End