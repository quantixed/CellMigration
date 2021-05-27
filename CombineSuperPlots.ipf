#pragma TextEncoding = "UTF-8"
#pragma rtGlobals=3		// Use modern global access method and strict wave access
#include "CellMigration"

Menu "CellMigr"
	"Combine SuperPlots...", /Q, CombineSuperplotWorkflow()
End

Function CombineSuperplotWorkflow()
	SetDataFolder root:
	// kill all windows and waves before we start
	CellMigration#CleanSlate()
	
	Variable cond = 2
	Variable pxps = 4
	
	Prompt cond, "How many conditions?"
	Prompt pxps, "How many pxps per condition?"
	DoPrompt "Specify", cond, pxps
	
	if (V_flag) 
		return -1
	endif
	
	Make/O/N=5 paramWave={cond,0,0,0,pxps}
	CellMigration#MakeColorWave(cond,"colorWave")
	CombineSuperplot_Panel(cond,pxps)
End

Function CombinedSuperPlot(mostTracks, reps)
	Variable mostTracks, reps
	
//	Wave/T/Z CondSplitWave = root:condSplitWave
	Wave/T/Z CondWave = root:condWave
//	WAVE/T labelWave = CellMigration#CleanUpCondWave(condSplitWave)
	WAVE/T labelWave = CellMigration#CleanUpCondWave(condWave)
//	CondSplitWave[] = CondWave[floor(p / reps)] + "_" + num2str(mod(p,reps) + 1)
	Variable cond = numpnts(condWave)
	Wave/Z colorWave = root:colorWave

	KillWindow/Z SuperPlot_cond
	Display/N=SuperPlot_cond
	KillWindow/Z SuperPlot_rep
	Display/N=SuperPlot_rep
	Variable nBin, binSize, loBin, hiBin
	Variable nRow, firstRow, inBin, maxNBin
	Variable groupWidth = 0.4 // this is hard-coded for now
	Variable alphaLevel = CellMigration#DecideOpacity(mostTracks)
	CellMigration#MakeColorWave(reps,"colorSplitWave")
	WAVE/Z colorSplitWave = root:colorSplitWave
	MakeColorWave(reps,"colorSplitWaveA", alpha = alphaLevel)
	WAVE/Z colorSplitWaveA = root:colorSplitWaveA
	String aveName, errName
	Make/O/N=(reps,cond)/FREE collatedMat
	
	String condName, dataFolderName, wName, wList, speedName
	Variable nTracks
	Variable i, j
	
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
//		wList = WaveList("cd_" + condName + "*", ";", "")
//		nTracks = ItemsInList(wList)
//		if(nTracks != numpnts(w))
//			DoAlert 0, "Check how the split data has compiled into the master wave"
//		endif
		speedName = "sum_Index_" + condName
//		Make/O/N=(nTracks) $speedName
		Wave indexW = $speedName
//		for(j = 0; j < nTracks; j += 1)
//			wName = StringFromList(j,wList)
//			wName = ReplaceString("cd_"+condName+"_",wName,"") // delete first bit
//			indexW[j] = str2num(wName[0]) - 1 // this gives the index (0-Based!)
//		endfor
//		// check that max here is the same as reps
//		if(WaveMax(indexW) + 1 != reps)
//			DoAlert 0, "Problem: please check how the split waves got reassembled"
//		endif
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
			if(DimSize(extractedValW,0) > 0)
				WaveStats/Q extractedValW
				w1[j][1] = V_Avg
				w2[j] = V_sem
			else
				w1[j][1] = NaN
				w2[j] = NaN
			endif
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
//		ErrorBars/W=SuperPlot_cond $aveName Y,wave=(w2,w2)
		// add to other superplot
		AppendToGraph/W=SuperPlot_rep $wName vs spSum_xWave
		ModifyGraph/W=SuperPlot_rep mode($wName)=3,marker($wName)=19
		ModifyGraph/W=SuperPlot_rep zColor($wName)={indexW,0,reps,cindexRGB,0,colorSplitWaveA}
		AppendToGraph/W=SuperPlot_rep w1[][1] vs w1[][0]
		ModifyGraph/W=SuperPlot_rep zColor($aveName)={w1[][3],0,reps,cindexRGB,0,colorSplitWave}
		ModifyGraph/W=SuperPlot_rep mode($aveName)=3,marker($aveName)=19,useMrkStrokeRGB($aveName)=1
		SetDataFolder root:
	endfor
	Label/W=SuperPlot_cond left "Average speed (\u03BCm/min)"
	SetAxis/A/N=1/E=1/W=SuperPlot_cond left
	Make/O/N=(numpnts(labelWave)) labelXWave = p
	ModifyGraph/W=SuperPlot_cond userticks(bottom)={labelXWave,labelWave}
	SetAxis/W=SuperPlot_cond bottom WaveMin(labelXWave) - 0.5, WaveMax(labelXWave) + 0.5
	Label/W=SuperPlot_rep left "Average speed (\u03BCm/min)"
	SetAxis/A/N=1/E=1/W=SuperPlot_rep left
	ModifyGraph/W=SuperPlot_rep userticks(bottom)={labelXWave,labelWave}
	SetAxis/W=SuperPlot_rep bottom WaveMin(labelXWave) - 0.5, WaveMax(labelXWave) + 0.5
	// do stats
	CellMigration#DoStatsAndLabel(collatedMat,"SuperPlot_rep")
	// add superplots to layout
//	AppendLayoutObject /W=summaryLayout graph SuperPlot_cond
//	AppendLayoutObject /W=summaryLayout graph SuperPlot_rep
End
	

// this function will load the required waves and make the calculation
// following this we can make the calculation about superplots groups
Function LoadSuperPlotSpeedWavesFromMultiplePXPs()

	NewDataFolder/O root:data
	Wave/T/Z condWave = root:condWave
	Wave/T/Z pathWave = root:pathwave1
	Variable nCond = numpnts(condWave)
	Variable nDF = numpnts(pathWave)
	// how many groups do we have?
	// a group is a superplot BUT we might not have all conditions present in each group
	// group likely = number of unique pxps
	Variable group = numpnts(pathWave) / numpnts(condWave)
	String wavePrefixToLoad = "sum_Speed_;sum_Index_;"
	Variable nWaves = ItemsInList(wavePrefixToLoad)
	
	Variable i,j
	
	// make data folders
	for(i = 0; i < nCond; i += 1)
		NewDataFolder/O $("root:data:" + condWave[i])
	endfor
	
	String thisPXP, cond, dfName, wName, newName
	Variable thisGroup
	
	for(i = 0; i < nDF; i += 1)
		thisPXP = pathWave[i]
		if(strlen(thisPXP) == 0)
			continue
		endif
		cond = condWave[floor(i / group)]
		dfName = "root:data:" + cond
		SetDataFolder(dfName)
		thisGroup = mod(i,group)
		for (j = 0; j < nWaves; j += 1)
			wName = StringFromList(j, wavePrefixToLoad) + cond
			LoadData/L=1/O/J=wName/S=dfName/Q thisPXP
			newName = wName + "_" + num2str(thisGroup)
			Rename $wName, $newName
		endfor
		SetDataFolder root:
	endfor
	
	Make/O/N=(group)/FREE maxPerGroup=0
	for(i = 0; i < group; i += 1)
		for (j = 0; j < nCond; j += 1)
			cond = condWave[j]
			Wave w = $("root:data:" + cond + ":sum_index_" + cond + "_" + num2str(i))
			if(numtype(WaveMax(w)) == 0)
				maxPerGroup[i] = max(maxPerGroup[i],WaveMax(w))
			endif
		endfor
	endfor
	// now we know what the maximum number of reps per group was and we need to set the index appropriately
	maxPerGroup += 1
	Integrate maxPerGroup
	for(i = 1; i < group; i += 1)
		for (j = 0; j < nCond; j += 1)
			cond = condWave[j]
			Wave w = $("root:data:" + cond + ":sum_index_" + cond + "_" + num2str(i))
			w += maxPerGroup[i - 1]
		endfor
	endfor
	// now concatenate the waves to leave us with the waves for superplotting
	String wList
	Variable mostCells = 0, maxGroup = 0
	for (i = 0; i < nCond; i += 1)
		cond = condWave[mod(i,nCond)]
		dfName = "root:data:" + cond
		SetDataFolder(dfName)
		for (j = 0; j < nWaves; j += 1)
			wList = WaveList(StringFromList(j, wavePrefixToLoad) + "*",";","")
			wName = StringFromList(j, wavePrefixToLoad) + cond
			Concatenate/O/KILL/NP=0 wList, $wName
			if(j == 1)
				Wave w = $wName
				mostCells = max(mostCells, numpnts(w))
				if(numtype(WaveMax(w)) == 0)
					maxGroup = max(maxGroup, WaveMax(w))
				endif
			endif
		endfor
	endfor
	
	SetDataFolder root:
	CombinedSuperPlot(mostCells, maxGroup + 1)
End

///	@param	cond	number of conditions - determines size of box
///	@param	reps	number of repitions - determines size of box
Function CombineSuperplot_Panel(cond, reps)
	Variable cond, reps
	
	Variable allCond = cond * reps
	Wave/Z colorWave = root:colorWave
	// make global text wave to store paths
	Make/T/O/N=(cond) condWave // store conditions
//	Make/T/O/N=(allCond) condSplitWave // store conditions subdivided
	Make/T/O/N=(allCond) PathWave1
	DoWindow/K FilePicker
	NewPanel/N=FilePicker/K=1/W=(40,40,840,150+30*allCond)
	// labelling of columns
	DrawText/W=FilePicker 10,30,"Name"
	DrawText/W=FilePicker 160,30,"Igor File (pxp)"
	DrawText/W=FilePicker 10,100+30*allCond,"CellMigration"
	// do it button
	Button DoIt,pos={680,70+30*allCond},size={100,20},proc=CSPDoItButtonProc,title="Do It"
	// insert rows
	String buttonName1a,buttonName1b,buttonName2a,buttonName2b,boxName0,boxName1,boxName2
	Variable i
	
	for(i = 0; i < allCond; i += 1)
		boxName0 = "box0_" + num2str(i)
		buttonName1b = "file1_" + num2str(i)
		boxName1 = "box1_" + num2str(i)
		buttonName2b = "file2_" + num2str(i)
		boxName2 = "box2_" + num2str(i)
		// row label
		DrawText/W=FilePicker 10,68+i*30,num2str(mod(i,reps)+1)
		// condition label
		SetVariable $boxName0,pos={30,53+i*30},size={100,14},value= condWave[floor(i/reps)], title=" "
		// file button
		Button $buttonName1b,pos={200,50+i*30},size={38,20},proc=ButtonProc,title="File"
		// file or dir box
		SetVariable $boxName1,pos={240,53+i*30},size={220,14},value= PathWave1[i], title=" "
		SetDrawEnv fillfgc=(colorWave[floor(i/reps)][0],colorWave[floor(i/reps)][1],colorWave[floor(i/reps)][2])
		DrawOval/W=FilePicker 130,50+i*30,148,68+i*30
	endfor
End


Function CSPDoItButtonProc(ctrlName) : ButtonControl
	String ctrlName
 	
 	WAVE/T CondWave, PathWave1
	Variable okvar = 0
	
	strswitch(ctrlName)	
		case "DoIt" :
			// check MasterCondWave
			okvar = CellMigration#WaveChecker(CondWave)
			if (okvar == -1)
				DoAlert 0, "Not all conditions have a name."
				break
			endif
			okvar = CellMigration#NameChecker(CondWave)
			if (okvar == -1)
				DoAlert 0, "Error: Two conditions have the same name."
				break
			endif
			okvar = CellMigration#WaveChecker(PathWave1)
			if (okvar == -1)
				Print "Note that not all conditions have a file to load."
			endif
			LoadSuperPlotSpeedWavesFromMultiplePXPs()
			KillWindow/Z FilePicker
	endswitch	
End