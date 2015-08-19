#pragma rtGlobals=3		// Use modern global access method and strict wave access.

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
	//call example LoadMigration(20,"control.xlsx","ctrl_")
	
	String sheet,prefix
	Variable i
	
	XLLoadWave/J=1
	Variable moviemax=ItemsInList(S_value)
	NewPath/O/Q path1, S_path
	
	For(i=0; i<moviemax; i+=1)
		sheet=StringFromList(i,S_Value)
		prefix=pref + num2str(i)
		XLLoadWave/S=sheet/R=(A1,H1000)/O/K=0/N=$prefix/P=path1 S_fileName
	Endfor
End


//This function will make cumulative distance waves for each cell. They are called cd_*
Function MakeTracks(pref)
	String pref
	String srch0= pref + "*_5"		//find all distance waves
	String srch1= pref + "*_1"		//find all track no waves
	String wList0=WaveList(srch0,";","")
	String wList1=WaveList(srch1,";","")
	Variable nWaves=ItemsInList(wList0)
	
	Variable nTrack
	String wName0,wName1,newName
	Variable i,j
	
	For(i=0; i<nWaves; i+=1)
		wName0=StringFromList(i,wList0)
		wName1=StringFromList(i,wList1)
		Wave w0=$wName0
		Wave w1=$wName1
		nTrack=WaveMax(w1)	//find maximum track no.
		For(j=1; j<(nTrack+1); j+=1)
			newName = "cd_" + wName0 + "_" + num2str(j)
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
			Endif
		EndFor
	Endfor
End

//This function will load the intensity data from an Excel Workbook with sheets named "Movie n"
Function LoadIntensity(moviemax,fname,pref)
	Variable moviemax
	String fname, pref
	//call example LoadMigration(20,"control.xlsx","ctrl_")
	
	String file="Macintosh HD:Users:steve:Documents:Lab People:Gabrielle Larocque:Migration Analysis:Expt1:" + fname
	
	String sheet,prefix
	Variable i,j
	
	For(i=0; i<moviemax; i+=1)
		sheet="movie " + num2str(i+1)
		prefix=ReplaceString("movie ",sheet,pref) + "_"
		XLLoadWave/S=sheet/R=(J2,K30)/COLT="T"/O/K=0/N=$prefix file
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
