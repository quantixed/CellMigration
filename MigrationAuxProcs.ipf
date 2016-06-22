#pragma rtGlobals=3		// Use modern global access method and strict wave access.

Function StitchIV()
	WAVE/Z/T sum_label
	Variable cond = numpnts(sum_label)
	String condName
	String wName0,wName1
	String preList,postList,plotName,newName
	Variable tempvar
	
	Variable i
	
	for(i = 0; i < cond; i += 2)
		wName0 = sum_label[i]
		wName1 = sum_label[i+1]
		tempvar = Stringmatch(wName0,"*pre*") + Stringmatch(wName1,"*post*")
		if(tempvar != 2)
			Print "Pre/Post Error"
			return 0
		endif
	endfor
	
	DoWindow/K cIVLayout
	NewLayout/N=cIVLayout
	DoWindow/K cIVPlot
	Display/N=cIVPlot
	
	Variable nWaves,aValue
	String avList,avName,errName
	Variable j
	
	for(i = 0; i < cond; i += 2)
		condName = sum_label[i]
		plotName = ReplaceString("pre",condName,"") + "_cIVplot"
		DoWindow/K $plotName
		Display/N=$plotName
		preList = WaveList("IV*" + condName + "*",";","")
		postList = ReplaceString("pre",preList,"post")
		nWaves = ItemsInList(preList)
		for(j = 0; j < nWaves; j += 1)
			wName0 = StringFromList(j, preList)
			wName1 = StringFromList(j, postList)
			Wave w0 = $wName0
			Wave/Z w1 = $wName1
			if(WaveExists(w1) == 1)
				// wave scaling from 1st wave use for concat wave
				Duplicate/O/FREE w0 w0s
				Duplicate/O/FREE w1 w1s
				aValue = mean(w0s,80,120)
				w0s /=aValue
				w1s /=aValue
				newName = "c_" + ReplaceString("pre",wName0,"_")
				Concatenate/O/NP {w0s,w1s}, $newName
				AppendToGraph/W=$plotName $newName
			endif
		endfor
		Wave/Z colorwave
		ModifyGraph /W=$plotName rgb=(colorwave[i][0],colorwave[i][1],colorwave[i][2])
		avList = Wavelist("c_iv*",";","WIN:"+ plotName)
		avName = "W_Ave_c_iv_" + ReplaceString("_",condName,"")
		errName = ReplaceString("Ave", avName, "Err")
		fWaveAverage(avList, "", 3, 1, AvName, ErrName)
		AppendToGraph /W=$plotName $avName
		DoWindow /F $plotName
		ErrorBars $avName Y,wave=($ErrName,$ErrName)
		ModifyGraph lsize($avName)=2,rgb($avName)=(0,0,0)
		SetAxis left 0,3
		Label left "Instantaneous velocity (µm/min)"
		Label bottom "Time (min)"
		AppendLayoutObject /W=cIVLayout graph $plotName
		
		AppendToGraph /W=cIVPlot $avName
		DoWindow /F cIVPlot
		ErrorBars $avName Y,wave=($ErrName,$ErrName)
		ModifyGraph lsize($avName)=2,rgb($avName)=(colorwave[i][0],colorwave[i][1],colorwave[i][2])
	endfor
	DoWindow /F cIVPlot
	SetAxis left 0,2
	Label left "Instantaneous velocity (µm/min)"
	Label bottom "Time (min)"
	AppendLayoutObject /W=cIVLayout graph $plotName
	AppendLayoutObject /W=cIVLayout graph cIVPlot
	// Tidy summary layout
	DoWindow /F cIVLayout
	// in case these are not captured as prefs
#if igorversion()>=7
	LayoutPageAction size(-1)=(595, 842), margins(-1)=(18, 18, 18, 18)
#endif
	ModifyLayout units=0
	ModifyLayout frame=0,trans=1
	Execute /Q "Tile"
End