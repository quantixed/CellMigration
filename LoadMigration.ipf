#pragma rtGlobals=3		// Use modern global access method and strict wave access.
#include <Waves Average>

//This will load all sheets of migration data from a specified excel file
//NOTE path is fixed - this means you need to edit it to read the excel files
//NOTE no headers in Excel file
//takes columns A-H max of 1000 rows
//columns are
//A - 0 - ImageJ row
//B - 1 - Track No
//C - 2 - Slice No
//D - 3 - x (in px)
//E - 4 - y (in px)
//F - 5 - distance
//G - 6 - velocity
//H - 7 - pixel value

//This function will load the tracking data from an Excel Workbook

Function LoadMigration(pref)
	String pref
	//call example LoadMigration("ctrl_")
	
	String sheet,prefix, wList
	Variable i
	
	XLLoadWave/J=1
	Variable moviemax=ItemsInList(S_value)
	NewPath/O/Q path1, S_path
	
	For(i=0; i<moviemax; i+=1)
		sheet=StringFromList(i,S_Value)
		prefix=pref + num2str(i)
		XLLoadWave/S=sheet/R=(A1,H1000)/O/K=0/N=$prefix/P=path1 S_fileName
		wList=wavelist(prefix + "*",";","")	//make matrices
		Concatenate/O/KILL wList, $prefix
	Endfor
End


//This function will make cumulative distance waves for each cell. They are called cd_*
//Scaling is set to 20 min
Function MakeTracks(pref)
	String pref
	
	String srch0= pref + "*"		//find all matrices
	String wList0=WaveList(srch0,";","")

	Variable nWaves=ItemsInList(wList0)
	
	Variable nTrack
	String mName0,newName,plotName,avList,avName,errName
	Variable i,j

	//cumulative distance and plot over time	
	plotName=pref + "cdplot"
	DoWindow /K $plotName	//set up plot
	Display /N=$plotName

	For(i=0; i<nWaves; i+=1)
		mName0=StringFromList(i,wList0)
		Wave m0=$mName0
		Duplicate/O/R=[][5] m0, w0	//distance
		Duplicate/O/R=[][1] m0, w1	//cell number
		Redimension /N=-1 w0, w1
		nTrack=WaveMax(w1)	//find maximum track no.
		For(j=1; j<(nTrack+1); j+=1)	//index is 1-based
			newName = "cd_" + mName0 + "_" + num2str(j)
			Duplicate/O w0 $newName
			Wave w2=$newName
			w2 = (w1==j) ? w0 : NaN
			WaveTransform zapnans w2
			If(numpnts(w2)==0)
				Killwaves w2
			Else
			w2[0]=0	//first point in distance trace is -1 so correct this
			Integrate/METH=0 w2	//make cumulative distance
			SetScale/P x 0,20,"min", w2
			AppendtoGraph /W=$plotName $newName
			Endif
		EndFor
	Endfor
	avlist=Wavelist("cd*",";","WIN:"+ plotName)
	avname="W_Ave" + pref
	errname=ReplaceString("Ave", avname, "Err")
	fWaveAverage(avlist, "", 3, 1, AvName, ErrName)
	AppendToGraph /W=$plotName $avname
	DoWindow /F $plotName
	ErrorBars $avname Y,wave=($ErrName,$ErrName)
	ModifyGraph lsize($avName)=2,rgb($avName)=(0,0,0)
	
	//plot out tracks
	plotName=pref + "tkplot"
	DoWindow /K $plotName	//set up plot
	Display /N=$plotName
	
	variable off
	
	For(i=0; i<nWaves; i+=1)
		mName0=StringFromList(i,wList0)
		Wave m0=$mName0
		Duplicate/O/R=[][3] m0, w0	//x pos
		Duplicate/O/R=[][4] m0, w1	//y pos
		Duplicate/O/R=[][1] m0, w2	//track number
		Redimension /N=-1 w0, w1,w2		
		nTrack=WaveMax(w2)	//find maximum track no.
		For(j=1; j<(nTrack+1); j+=1)	//index is 1-based
			newName = "tk_" + mName0 + "_" + num2str(j)
			Duplicate/O w0 w3
			w3 = (w2==j) ? w3 : NaN
			WaveTransform zapnans w3
			If(numpnts(w3)==0)
				Killwaves w3
			Else
			off=w3[0]
			w3 -=off	//set to origin
			w3 *=0.32
			//do the y wave
			Duplicate/O w1 w4
			w4 = (w2==j) ? w4 : NaN
			WaveTransform zapnans w4
			off=w4[0]
			w4 -=off
			w4 *=0.32
			Concatenate/O/KILL {w3,w4}, $newName
			Wave w5=$newName
			AppendtoGraph /W=$plotName w5[][1] vs w5[][0]
			Endif
		EndFor
	Endfor
	DoWindow /F $plotName
	SetAxis left -250,250;DelayUpdate
	SetAxis bottom -250,250;DelayUpdate
	ModifyGraph width={Plan,1,bottom,left};DelayUpdate
	ModifyGraph mirror=1;DelayUpdate
	ModifyGraph grid=1
End

//This function will load the intensity data from an Excel Workbook **Updated but Untested**
Function LoadIntensity(pref)
	String pref
	
	XLLoadWave/J=1
	Variable moviemax=ItemsInList(S_value)
	NewPath/O/Q path1, S_path
	
	String sheet,prefix
	Variable i,j
	
	For(i=0; i<moviemax; i+=1)
		sheet=StringFromList(i,S_Value)
		prefix=pref + num2str(i)
		XLLoadWave/S=sheet/R=(J2,K30)/COLT="T"/O/K=0/N=$prefix/P=path1 S_fileName
	Endfor
	
	String wList=WaveList(pref + "*_0",";","")
	Variable nWaves=ItemsInList(wList)
	String wName,newName, cell
	Variable nCells
	
	//change waves to give the correct reference to the cd_ wave
	For(i=0; i<nWaves; i+=1)
		wName=StringFromList(i,wList)
		newName=ReplaceString(pref,wName,"cd_tpd_")	//will need changing
		Wave/T w0=$wName
		nCells=numpnts(w0)
		For(j=0; j<nCells; j+=1)
			cell=ReplaceString("_0",newName,"_5_") + w0[j]
			w0[j]=cell
		EndFor
	Endfor
	//concatenate them
	Concatenate/O wList, cellWave
	//kill originals
	For(i=0; i<nWaves; i+=1)
		wName=StringFromList(i,wList)
		Wave/T w0=$wName
		KillWaves w0 
	Endfor
	
	//Process text waves
	wList=WaveList(pref + "*_1",";","")
	nWaves=ItemsInList(wList)
	Variable numint
	String IntText="very low;low;mid;high;very high;"
	//change waves to give numeric value
	For(i=0; i<nWaves; i+=1)
		wName=StringFromList(i,wList)
		newName="num" + wName
		Wave/T w0=$wName
		nCells=numpnts(w0)
		Make/O/N=(nCells) $newName
		Wave w1=$newName
		For(j=0; j<nCells; j+=1)
			cell=w0[j]
			numint=WhichListItem(cell, intText)
			w1[j]=numint
		EndFor
		KillWaves w0	//kill text waves after processing
	Endfor
	//concatenate them
	wList=WaveList("num*",";","")
	Concatenate/O wList, IntWave
	//kill individuals
	For(i=0; i<nWaves; i+=1)
		wName=StringFromList(i,wList)
		Wave/T w0=$wName
		KillWaves w0 
	Endfor
	
	DoWindow /K Plot0	//set up plot for very low traces
	Display /N=Plot0
	DoWindow /K Plot1	//set up plot for low traces
	Display /N=Plot1
	DoWindow /K Plot2	//set up plot for mid traces
	Display /N=Plot2
	DoWindow /K Plot3	//set up plot for high traces
	Display /N=Plot3
	DoWindow /K Plot4	//set up plot for very high traces
	Display /N=Plot4

	nCells=numpnts(cellWave)
	String pName
	Wave/T w0=cellWave
	Wave IntWave
	For(i=0; i<nCells; i+=1)
		cell=w0[i]
		Wave w1=$cell
		numint=IntWave[i]
		pName="Plot" + num2str(numint)
		AppendtoGraph /W=$pName w1
	EndFor
End
