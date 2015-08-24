# CellMigration
Analysis of cell migration in Igor Pro

This is a set of functions to load and analyse cell migration in Igor.
Particles are tracked manually in ImageJ/FIJI.

Migrate function
----------------

LoadMigration.ipf contains three procedures to analyse cell migration in IgorPro.<br />
Use ImageJ to track the cells. Outputs from tracking are saved in sheets in an Excel Workbook, 1 per condition.<br />
Execute <code>Migrate(n)</code> to specify the load of n experimental conditions.<br />
This function will trigger the load and the analysis of cell migration via two functions.

* <code>LoadMigration()</code> - will load all sheets of migration data from a specified excel file
* <code>MakeTracks()</code> - does the analysis

The dialog asks the user to name the condition prefix, e.g. "Ctrl_". Quotes and underscore are required.<br />
User picks the Excel workbook and clicks OK on LoadData window. Igor Will do the rest!

### Excel formatting

NOTE no headers in Excel file keep data to columns A-H, max of 1000 rows

* A - 0 - ImageJ row
* B - 1 - Track No
* C - 2 - Slice No
* D - 3 - x (in px)
* E - 4 - y (in px)
* F - 5 - distance
* G - 6 - velocity
* H - 7 - pixel value

### Colour palettes
Colours are taken from Paul Tol SRON stylesheet
