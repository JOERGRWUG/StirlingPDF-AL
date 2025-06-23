codeunit 50995 StirlingPDFAPI
{
    trigger OnRun()
    var
        blob: Codeunit "Temp Blob";
        blob1: Codeunit "Temp Blob";
        blob2: Codeunit "Temp Blob";
        filename: Text;
    begin
        DebugMode := true;
        filename := FileManagement.BLOBImportWithFilter(blob, '', '', 'PDF Files (*.pdf)|*.pdf', '*.pdf');
        filename := FileManagement.BLOBImportWithFilter(blob1, '', '', 'PDF Files (*.pdf)|*.pdf', '*.pdf');
        //EncryptFile(blob, filename, '123', '123', blob2);
        Merge(blob, '1.pdf', blob1, '2.pdf', blob2);
        //Message('%1', PageCount(blob, 'test.pdf'));
        FileManagement.BLOBExport(blob2, 'output.pdf', true);
    end;

    PROCEDURE EncryptFile(VAR FileTempBlob_p: Codeunit "Temp Blob"; Filename_p: Text; OwnerPassword_p: Text; FilePassword_p: Text; VAR ResponseTempBlob_p: Codeunit "Temp Blob"): Boolean;
    var
        OutStream_l: OutStream;
    BEGIN
        IF NOT FileTempBlob_p.HasValue() then
            ERROR('Empty Blob');

        InitContent();
        AddTextParameterToContent('keyLength', '256');
        AddTextParameterToContent('ownerPassword', OwnerPassword_p);
        AddTextParameterToContent('password', FilePassword_p);
        AddBoolParameterToContent('canExtractContent', false);
        AddBoolParameterToContent('canPrint', false);
        AddBoolParameterToContent('canPrintFaithful', false);
        AddBoolParameterToContent('canFillInForm', false);
        AddBoolParameterToContent('canModifyAnnotations', false);
        AddBoolParameterToContent('canAssembleDocument', FALSE);
        AddBoolParameterToContent('canExtractForAccessibility', FALSE);
        AddBoolParameterToContent('canModify', FALSE);
        AddFileToContent(FileTempBlob_p, Filename_p);
        FinalizeContent();

        if DebugMode then
            FileManagement.BLOBExport(ContentTempBlob, 'content.txt', true);

        CallAPI('/security/add-password', 'POST', ResponseTempBlob_p);
    END;

    PROCEDURE Merge(VAR File1TempBlob_p: Codeunit "Temp Blob"; Filename1_p: Text; VAR File2TempBlob_p: Codeunit "Temp Blob"; Filename2_p: Text; VAR ResponseTempBlob_p: Codeunit "Temp Blob"): Boolean;
    var
        OutStream_l: OutStream;
        ResponseContent_l: Text;
    BEGIN
        InitContent();
        AddTextParameterToContent('sortType', 'orderProvided');
        AddFileToContent(File1TempBlob_p, Filename1_p);
        AddFileToContent(File2TempBlob_p, Filename2_p);
        FinalizeContent();

        if DebugMode then
            FileManagement.BLOBExport(ContentTempBlob, 'content.txt', true);

        CallAPI('/general/merge-pdfs', 'POST', ResponseTempBlob_p);
    END;

    PROCEDURE PageCount(VAR FileAsBlob_p: Codeunit "Temp Blob"; Filename_p: Text): Integer;
    var
        JsonManagement_l: Codeunit "JSON Management";
        ResponseTempBlob_l: Codeunit "Temp Blob";
        Decimal_l: Decimal;
        InStream_l: InStream;
        JsonObject_l: JsonObject;
    BEGIN
        InitContent();
        AddFileToContent(FileAsBlob_p, Filename_p);
        FinalizeContent();

        CallAPI('/analysis/page-count', 'POST', ResponseTempBlob_l);

        ResponseTempBlob_l.CreateInStream(InStream_l);
        JsonObject_l.ReadFrom(InStream_l);
        Decimal_l := JsonObject_l.GetDecimal('pageCount');
        exit(Decimal_l DIV 1)
    END;

    LOCAL PROCEDURE CallAPI(Action_p: Text; Method_p: Text; VAR ResponseTempBlob_p: Codeunit "Temp Blob") Success_r: Boolean;
    VAR
        Client_l: HttpClient;
        Content_l: HttpContent;
        ContentHeaders_l: HttpHeaders;
        InStream_l: InStream;
        OutStream_l: OutStream;
        Request_l: HttpRequestMessage;
        RequestHeaders_l: HttpHeaders;
        Response_l: HttpResponseMessage;
        ResponseHeaders_l: HttpHeaders;
    BEGIN
        Initialize;

        ContentTempBlob.CreateInStream(InStream_l);
        Content_l.WriteFrom(InStream_l);
        Content_l.GetHeaders(ContentHeaders_l);
        ContentHeaders_l.Clear();
        ContentHeaders_l.Add('Content-Type', STRSUBSTNO('multipart/form-data;boundary=%1', GetBoundary));

        Request_l.GetHeaders(RequestHeaders_l);
        RequestHeaders_l.Add('Accept-Language', ClientLanguage);

        Request_l.Content := Content_l;
        Request_l.Method := Method_p;
        Request_l.SetRequestUri(StirlingAPI + Action_p);
        if Client_l.Send(Request_l, Response_l) then begin
            Response_l.Content.ReadAs(InStream_l);
            ResponseTempBlob_p.CreateOutStream(OutStream_l);
            CopyStream(OutStream_l, InStream_l);
            Success_r := true;
        end else begin
            ResponseHeaders_l := Response_l.Headers();
            Error('ERR: ' + Format(ResponseHeaders_l.Keys()));
        end;
    END;

    LOCAL PROCEDURE AddBoolParameterToContent(Name_p: Text; Value_p: Boolean);
    BEGIN
        IF Value_p THEN
            AddTextParameterToContent(Name_p, 'true')
        ELSE
            AddTextParameterToContent(Name_p, 'false');
    END;

    LOCAL PROCEDURE AddFileToContent(VAR FileTempBlob_p: Codeunit "Temp Blob"; Filename_p: Text);
    var
        DotNetEncoding_l: Codeunit DotNet_Encoding;
        DotNetStreamReader_l: Codeunit DotNet_StreamReader;
        InStream_l: InStream;
    BEGIN
        ContentOutStream.WriteText(GetBoundaryStart());
        ContentOutStream.WriteText(TypeHelper.CRLFSeparator());
        ContentOutStream.WriteText(STRSUBSTNO('Content-Disposition: form-data; name=fileInput; filename="%1"', Filename_p));
        ContentOutStream.WriteText(TypeHelper.CRLFSeparator());
        ContentOutStream.WriteText('Content-Type: application/pdf');
        ContentOutStream.WriteText(TypeHelper.CRLFSeparator());
        ContentOutStream.WriteText(TypeHelper.CRLFSeparator());

        FileTempBlob_p.CreateInStream(InStream_l);
        DotNetEncoding_l.Encoding(1252);
        DotNetStreamReader_l.StreamReader(InStream_l, DotNetEncoding_l);
        ContentOutStream.WriteText(DotNetStreamReader_l.ReadToEnd());

        ContentOutStream.WriteText(TypeHelper.CRLFSeparator());
    END;

    LOCAL PROCEDURE AddTextParameterToContent(Name_p: Text; Value_p: Text);
    var
        InStream_l: InStream;
    BEGIN
        ContentOutStream.WriteText(GetBoundaryStart());
        ContentOutStream.WriteText(TypeHelper.CRLFSeparator());
        ContentOutStream.WriteText(STRSUBSTNO('Content-Disposition: form-data; name="%1"', Name_p));
        ContentOutStream.WriteText(TypeHelper.CRLFSeparator());
        ContentOutStream.WriteText(TypeHelper.CRLFSeparator());
        ContentOutStream.WriteText(Value_p);
        ContentOutStream.WriteText(TypeHelper.CRLFSeparator());
    END;

    local procedure InitContent()
    begin
        Clear(ContentOutStream);
        Clear(ContentTempBlob);
        ContentOutStream := ContentTempBlob.CreateOutStream(TextEncoding::Windows);
    end;

    local procedure FinalizeContent()
    begin
        ContentOutStream.WriteText(STRSUBSTNO('--%1--', GetBoundary));
    end;

    LOCAL PROCEDURE GetBoundary(): Text;
    BEGIN
        EXIT('--SuS');
    END;

    LOCAL PROCEDURE GetBoundaryStart(): Text;
    BEGIN
        EXIT(STRSUBSTNO('--%1', GetBoundary));
    END;

    LOCAL PROCEDURE Initialize();
    BEGIN
        CLEARLASTERROR;

        IF Initialized THEN
            EXIT;

        StirlingAPI := 'https://stirling-pdf.intranet-dev.intern.schmitt-aufzuege.com/api/v1';
        ClientLanguage := 'en';
        Initialized := TRUE;
    END;


    VAR
        FileManagement: Codeunit "File Management";
        ContentTempBlob: Codeunit "Temp Blob";
        TypeHelper: Codeunit "Type Helper";
        ClientLanguage: Text;
        ContentOutStream: OutStream;
        DebugMode: Boolean;
        Initialized: Boolean;
        StirlingAPI: Text;
}    
}
