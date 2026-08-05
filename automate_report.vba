' ==============================================================================
' STA RIDE - Professional Report Automation Macro (TOC, LOF, LOT)
' Use this in MS Word to automatically format your report and generate tables.
' ==============================================================================

Sub FinalizeSTA_Report()
    Dim doc As Document
    Set doc = ActiveDocument

    Application.ScreenUpdating = False

    ' 1. Initial Formatting
    SetupPageLayout doc
    CreateStyles doc

    ' 2. Identify and Style Content
    ApplyHeadingsAndCaptions doc

    ' 3. Insert Automation Fields (TOC, LOF, LOT)
    InsertTablesOfContents doc

    ' 4. Final Updates
    doc.Fields.Update
    Application.ScreenUpdating = True

    MsgBox "STA RIDE Report Automation Complete!" & vbCrLf & _
           "- Table of Contents Generated" & vbCrLf & _
           "- List of Figures Generated" & vbCrLf & _
           "- List of Tables Generated", vbInformation, "Success"
End Sub

Sub SetupPageLayout(doc As Document)
    With doc.PageSetup
        .PaperSize = wdPaperA4
        .TopMargin = InchesToPoints(1)
        .BottomMargin = InchesToPoints(1)
        .LeftMargin = InchesToPoints(1.5) ' Gutter for binding
        .RightMargin = InchesToPoints(1)
    End With
End Sub

Sub CreateStyles(doc As Document)
    ' Heading 1 (Chapters & Main Pages)
    With doc.Styles(wdStyleHeading1).Font
        .Name = "Poppins"
        .Size = 16
        .Bold = True
        .AllCaps = True
        .Color = wdColorGold
    End With

    ' Heading 2 (Sections)
    With doc.Styles(wdStyleHeading2).Font
        .Name = "Poppins"
        .Size = 13
        .Bold = True
        .Color = wdColorBlack
    End With

    ' Caption Style for Figures and Tables
    On Error Resume Next
    Dim capStyle As Style
    Set capStyle = doc.Styles.Add(Name:="STA_Caption", Type:=wdStyleTypeParagraph)
    With capStyle.Font
        .Name = "Poppins"
        .Size = 10
        .Italic = True
        .Bold = True
    End With
    On Error GoTo 0
End Sub

Sub ApplyHeadingsAndCaptions(doc As Document)
    Dim para As Paragraph
    For Each para In doc.Paragraphs
        Dim txt As String
        txt = Trim(para.Range.Text)

        ' Apply Heading 1 to Chapters and Preliminaries
        If txt Like "CHAPTER *" Or txt Like "ACKNOWLEDGEMENT*" Or _
           txt Like "SUMMARY*" Or txt Like "TABLE OF CONTENTS*" Or _
           txt Like "LIST OF *" Or txt Like "REFERENCES*" Or _
           txt Like "APPENDICES*" Then
            para.Style = doc.Styles(wdStyleHeading1)
            If Not (txt Like "TABLE OF CONTENTS*") Then
                para.Range.InsertBreak Type:=wdPageBreak
            End If

        ' Apply Heading 2 to Numbered Sections (e.g. 1.1, 2.1)
        ElseIf txt Like "[0-9].[0-9]*" Then
            para.Style = doc.Styles(wdStyleHeading2)

        ' Apply Caption Style to Figures
        ElseIf txt Like "Figure [0-9].[0-9]*" Then
            para.Style = "STA_Caption"

        ' Apply Caption Style to Tables
        ElseIf txt Like "Table [0-9].[0-9]*" Then
            para.Style = "STA_Caption"
        End If
    Next para
End Sub

Sub InsertTablesOfContents(doc As Document)
    Dim rng As Range

    ' --- 1. TABLE OF CONTENTS ---
    ' Search for the "TABLE OF CONTENTS" text to place the field under it
    Set rng = FindTextRange(doc, "TABLE OF CONTENTS")
    If Not rng Is Nothing Then
        rng.Collapse wdCollapseEnd
        rng.InsertAfter vbCrLf
        doc.TablesOfContents.Add Range:=rng, UseHeadingStyles:=True, _
            UpperHeadingLevel:=1, LowerHeadingLevel:=3, _
            RightAlignPageNumbers:=True, IncludePageNumbers:=True
    End If

    ' --- 2. LIST OF FIGURES ---
    Set rng = FindTextRange(doc, "LIST OF FIGURES")
    If Not rng Is Nothing Then
        rng.Collapse wdCollapseEnd
        rng.InsertAfter vbCrLf
        doc.TablesOfFigures.Add Range:=rng, Caption:="Figure", _
            IncludeLabel:=True, RightAlignPageNumbers:=True, _
            UseHeadingStyles:=False, IncludePageNumbers:=True
    End If

    ' --- 3. LIST OF TABLES ---
    Set rng = FindTextRange(doc, "LIST OF TABLES")
    If Not rng Is Nothing Then
        rng.Collapse wdCollapseEnd
        rng.InsertAfter vbCrLf
        doc.TablesOfFigures.Add Range:=rng, Caption:="Table", _
            IncludeLabel:=True, RightAlignPageNumbers:=True, _
            UseHeadingStyles:=False, IncludePageNumbers:=True
    End If
End Sub

Function FindTextRange(doc As Document, txt As String) As Range
    Dim rng As Range
    Set rng = doc.Content
    With rng.Find
        .Text = txt
        .Forward = True
        .Wrap = wdFindStop
        If .Execute Then
            Set FindTextRange = rng
        Else
            Set FindTextRange = Nothing
        End If
    End With
End Function
