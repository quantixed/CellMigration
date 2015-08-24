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

//Define colours
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

Function hexcolor_red(hex)
    Variable hex
    return byte_value(hex, 2) * 2^8
End

Function hexcolor_green(hex)
    Variable hex
    return byte_value(hex, 1) * 2^8
End

Function hexcolor_blue(hex)
    Variable hex
    return byte_value(hex, 0) * 2^8
End

Static Function byte_value(data, byte)
    Variable data
    Variable byte
    return (data & (0xFF * (2^(8*byte)))) / (2^(8*byte))
End


//Loads the data and performs migration analysis
Function Migrate(cond)
	Variable cond //how many conditions?
	//call example Migrate(2)
	
	//kill all windows and waves
	string fulllist = WinList("*", ";","WIN:3")
	string name
	variable i
 
	for(i=0; i<ItemsInList(fulllist); i +=1)
		name= StringFromList(i, fulllist)
		DoWindow/K $name		
	endfor
	
	KillWaves/A/Z
	
	//Pick colours from SRON palettes
	String pal
	if(cond==1)
		pal = SRON_1
	elseif(cond==2)
		pal = SRON_2
	elseif(cond==3)
		pal = SRON_3
	elseif(cond==4)
		pal = SRON_4
	elseif(cond==5)
		pal = SRON_5
	else
		pal = SRON_12
	endif

	Make/O/N=(cond,3) colorwave
	Make/O/T/N=(cond) sum_Label
	Make/O/N=(cond) sum_MeanSpeed
	Make/O/N=(cond) sum_SemSpeed
	Make/O/N=(cond) sum_NSpeed
	
	String pref,lab
	Variable color
	Variable /G gR,gG,gB
	
	DoWindow /K cdPlot
	Display /N=cdPlot
	DoWindow /K dDPlot
	Display /N=dDPlot
	DoWindow /K MSDPlot
	Display /N=MSDPlot
	
	For(i=1; i<cond+1; i+=1)
		Prompt pref, "Experimental condition e.g. \"ctrl_\", \"tacc3_\". Quotes + underscore required"
		DoPrompt "Describe conditions", pref
		
		if(V_Flag)
      			Abort "The user pressed Cancel"
		endif
		
		lab=ReplaceString("_",pref,"")
		sum_Label[i-1]=lab
		
		//specify colours
		if(cond<6)
			color=str2num(StringFromList(i-1,pal))
			gR=hexcolor_red(color)
			gG=hexcolor_green(color)
			gB=hexcolor_blue(color)
		else
			color=str2num(StringFromList(round((i-1)/12),pal))
			gR=hexcolor_red(color)
			gG=hexcolor_green(color)
			gB=hexcolor_blue(color)
		endif
		colorwave[i-1][0]=gR //offset by one because cond is 1-based
		colorwave[i-1][1]=gG
		colorwave[i-1][2]=gB
		//run other procedures
		LoadMigration(pref)
		MakeTracks(pref)
	EndFor
	
	//Tidy up summary windows
	DoWindow /F cdPlot
	SetAxis/A/N=1 left
	Label left "Cumulative distance (µm)"
	Label bottom "Time (min)"
	
	DoWindow /F dDPlot
	Label left "Directionality ratio (d/D)"
	Label bottom "Time (min)"
	
	DoWindow /F MSDPlot
	ModifyGraph log=1
	SetAxis/A/N=1 left
	String wName=StringFromList(0,WaveList("W_Ave*",";","WIN:"))
	SetAxis bottom 20,((numpnts($wName)*20)/2)
	Label left "MSD"
	Label bottom "Time (min)"
	
	//average data	
	String wList, newName
	Variable nTracks,last,j
	
	For(i=0; i<cond; i+=1) //loop through conditions 0-based
		pref=sum_Label[i] + "_"
		wList=WaveList("cd_" + pref + "*", ";","")
		nTracks=ItemsInList(wList)
		newName="Sum_Speed_" + ReplaceString("_",pref,"")
		Make/O/N=(nTracks) $newName
		Wave w0=$newName
		For(j=0; j<nTracks; j+=1)
			wName=StringFromList(j,wList)
			Wave w1=$wName
			last=numpnts(w1)
			w0[j]=w1[last-1]/((last-1)*20)	//scaling
		Endfor
		WaveStats/Q w0
		sum_MeanSpeed[i]=V_avg
		sum_SemSpeed[i]=V_sem
		sum_NSpeed[i]=V_npnts
	Endfor
	DoWindow /K SpeedTable
	Edit /N=SpeedTable sum_Label,sum_MeanSpeed,sum_MeanSpeed,sum_SemSpeed,sum_NSpeed
	DoWindow /K SpeedPlot
	Display /N=SpeedPlot sum_MeanSpeed vs sum_Label
	Label left "Speed (µm/min)";DelayUpdate
	SetAxis/A/N=1/E=1 left
	ErrorBars sum_MeanSpeed Y,wave=(sum_SemSpeed,sum_SemSpeed)
	ModifyGraph zColor(sum_MeanSpeed)={colorwave,*,*,directRGB,0}
	ModifyGraph hbFill=2
	AppendToGraph/R sum_MeanSpeed vs sum_Label
	SetAxis/A/N=1/E=1 right
	ModifyGraph hbFill(sum_MeanSpeed#1)=0,rgb(sum_MeanSpeed#1)=(0,0,0)
	ModifyGraph noLabel(right)=2,axThick(right)=0,standoff(right)=0
	ErrorBars sum_MeanSpeed#1 Y,wave=(sum_SemSpeed,sum_SemSpeed)

	Execute "TileWindows/O=3/C"
End

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
	
	NVAR cR=gR
	NVAR cG=gG
	NVAR cB=gB
	
	String wList0=WaveList(pref + "*",";","") //find all matrices

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
		For(j=1; j<(nTrack+2); j+=1)	//index is 1-based, plus 2 was needed.
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
		DoWindow /F $plotName
	Endfor
	ModifyGraph /W=$plotName rgb=(cR,cG,cB)
	avlist=Wavelist("cd*",";","WIN:"+ plotName)
	avname="W_Ave_cd_" + ReplaceString("_",pref,"")
	errname=ReplaceString("Ave", avname, "Err")
	fWaveAverage(avlist, "", 3, 1, AvName, ErrName)
	AppendToGraph /W=$plotName $avname
	DoWindow /F $plotName
	Label left "Cumulative distance (µm)"
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
	ModifyGraph /W=$plotName rgb=(cR,cG,cB)
	SetAxis left -250,250;DelayUpdate
	SetAxis bottom -250,250;DelayUpdate
	ModifyGraph width={Plan,1,bottom,left};DelayUpdate
	ModifyGraph mirror=1;DelayUpdate
	ModifyGraph grid=1
	
	//calculate d/D directionality ratio
	plotName=pref + "dDplot"
	DoWindow /K $plotName	//set up plot
	Display /N=$plotName
	
	String wName0,wName1
	Variable len
	wList0=WaveList("tk_" + pref + "*", ";","")
	nWaves=ItemsInList(wList0)
	
	For(i=0; i<nWaves; i+=1)
		wName0=StringFromList(i,wList0)			//tk wave
		wName1=ReplaceString("tk",wName0,"cd")	//cd wave
		Wave w0=$wName0
		Wave w1=$wName1
		newName=ReplaceString("tk",wName0,"dD")
		Duplicate/O w1 $newName
		Wave w2=$newName
		len=numpnts(w2)
		w2=1
		For(j=1; j<len; j+=1)
			w2[j]= sqrt(w0[j][0]^2 + w0[j][1]^2)/w1[j]
		EndFor
		AppendtoGraph /W=$plotName w2
	Endfor
	ModifyGraph /W=$plotName rgb=(cR,cG,cB)
	avlist=Wavelist("dD*",";","WIN:"+ plotName)
	avname="W_Ave_dD_" + ReplaceString("_",pref,"")
	errname=ReplaceString("Ave", avname, "Err")
	fWaveAverage(avlist, "", 3, 1, AvName, ErrName)
	AppendToGraph /W=$plotName $avname
	DoWindow /F $plotName
	Label left "Directionality ratio (d/D)"
	Label bottom "Time (min)"
	ErrorBars $avname Y,wave=($ErrName,$ErrName)
	ModifyGraph lsize($avName)=2,rgb($avName)=(0,0,0)
	
	//calculate MSD (overlapping method)
	plotName=pref + "MSDplot"
	DoWindow /K $plotName	//set up plot
	Display /N=$plotName
	wList0=WaveList("tk_" + pref + "*", ";","")
	nWaves=ItemsInList(wList0)
	Variable k
	
	For(i=0; i<nWaves; i+=1)
		wName0=StringFromList(i,wList0)			//tk wave
		Wave w0=$wName0
		len=DimSize(w0,0)
		mName0=ReplaceString("tk",wName0,"MSDtemp")
		newName=ReplaceString("tk",wName0,"MSD")	//for results of MSD per cell
		Make/O/N=(len,len-1) $mName0=NaN //not sure about len/2
		Wave m0=$mName0
		For(k=0; k<len-1; k+=1)	//by col
			For(j=1; j<len; j+=1)	//by row
				If(j>k)
					m0[j][k]= ((w0[j][0] - w0[j-(k+1)][0])^2)+((w0[j][1] - w0[j-(k+1)][1])^2)
				Endif
			EndFor
		EndFor
		Make/O/N=(len+1) $newName=NaN
		Wave w2=$newName
		//extract cell MSDs per time point
		For(k=0;k<len; k+=1)
			Duplicate/O/R=[][k] m0, w1 //no need to redimension or zapnans
			Wavestats/Q w1			
			w2[k+1]=v_avg
		EndFor
		SetScale/P x 0,20,"min", w2
		AppendtoGraph /W=$plotName w2
	Endfor
	KillWaves m0	//removed killwaves w1 as it created an error
	ModifyGraph /W=$plotName rgb=(cR,cG,cB)
	avlist=Wavelist("MSD*",";","WIN:"+ plotName)
	avname="W_Ave_MSD_" + ReplaceString("_",pref,"")
	errname=ReplaceString("Ave", avname, "Err")
	fWaveAverage(avlist, "", 3, 1, AvName, ErrName)
	AppendToGraph /W=$plotName $avname
	DoWindow /F $plotName
	ModifyGraph log=1
	SetAxis/A/N=1 left
	len=numpnts($avName)*20
	SetAxis bottom 20,(len/2)
	Label left "MSD"
	Label bottom "Time (min)"
	ErrorBars $avname Y,wave=($ErrName,$ErrName)
	ModifyGraph lsize($avName)=2,rgb($avName)=(0,0,0)
	
	//Plot these summary windows at the end
	avname="W_Ave_cd_" + ReplaceString("_",pref,"")
	errname=ReplaceString("Ave", avname, "Err")
	AppendToGraph /W=cdPlot $avname
	DoWindow /F cdPlot
	ErrorBars $avname Y,wave=($ErrName,$ErrName)
	ModifyGraph lsize($avName)=2,rgb($avName)=(cR,cG,cB)
	
	avname="W_Ave_dD_" + ReplaceString("_",pref,"")
	errname=ReplaceString("Ave", avname, "Err")
	AppendToGraph /W=dDPlot $avname
	DoWindow /F dDPlot
	ErrorBars $avname Y,wave=($ErrName,$ErrName)
	ModifyGraph lsize($avName)=2,rgb($avName)=(cR,cG,cB)
			
	avname="W_Ave_MSD_" + ReplaceString("_",pref,"")
	errname=ReplaceString("Ave", avname, "Err")
	AppendToGraph /W=MSDPlot $avname
	DoWindow /F MSDPlot
	ErrorBars $avname Y,wave=($ErrName,$ErrName)
	ModifyGraph lsize($avName)=2,rgb($avName)=(cR,cG,cB)
End
