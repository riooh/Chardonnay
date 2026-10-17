// SPDX-License-Identifier: MIT
// Build a real registry-only MSI package through Windows Installer APIs.
// This creates no installed game, client, credentials or public Desktop shortcut.
#ifndef UNICODE
#define UNICODE
#endif
#ifndef _UNICODE
#define _UNICODE
#endif
#include <windows.h>
#include <msi.h>
#include <msiquery.h>
#include <stdio.h>

static int sql(MSIHANDLE database,const wchar_t *statement){
    MSIHANDLE view=0;UINT result=MsiDatabaseOpenViewW(database,statement,&view);
    if(result==ERROR_SUCCESS)result=MsiViewExecute(view,0);
    if(view)MsiCloseHandle(view);
    if(result!=ERROR_SUCCESS){
        fwprintf(stderr,L"MSI SQL failed %u: %ls\n",result,statement);
        FILE *log=fopen("C:\\ChardonnayFixture-msi-build.txt","a");
        char text[32768];WideCharToMultiByte(CP_UTF8,0,statement,-1,text,sizeof(text),NULL,NULL);
        if(log){fprintf(log,"sql_error=%u\n%s\n",result,text);fclose(log);}
    }
    return (int)result;
}
int wmain(int argc,wchar_t **argv){
    if(argc!=2)return 2;
    MSIHANDLE db=0,summary=0;
    UINT result=MsiOpenDatabaseW(argv[1],MSIDBOPEN_CREATE,&db);if(result)return (int)result;
    const wchar_t *statements[]={
        L"CREATE TABLE `Property` (`Property` CHAR(72) NOT NULL, `Value` CHAR(0) LOCALIZABLE PRIMARY KEY `Property`)",
        L"INSERT INTO `Property` (`Property`, `Value`) VALUES ('ProductCode','{8C762F94-12D8-42DD-9AAB-12C101330101}')",
        L"INSERT INTO `Property` (`Property`, `Value`) VALUES ('UpgradeCode','{8C762F94-12D8-42DD-9AAB-12C101330102}')",
        L"INSERT INTO `Property` (`Property`, `Value`) VALUES ('ProductName','Chardonnay Private MSI Fixture')",
        L"INSERT INTO `Property` (`Property`, `Value`) VALUES ('ProductVersion','1.0.0')",
        L"INSERT INTO `Property` (`Property`, `Value`) VALUES ('ProductLanguage','1033')",
        L"INSERT INTO `Property` (`Property`, `Value`) VALUES ('Manufacturer','Chardonnay Tests')",
        L"INSERT INTO `Property` (`Property`, `Value`) VALUES ('ALLUSERS','')",
        L"CREATE TABLE `Directory` (`Directory` CHAR(72) NOT NULL, `Directory_Parent` CHAR(72), `DefaultDir` CHAR(255) NOT NULL LOCALIZABLE PRIMARY KEY `Directory`)",
        L"INSERT INTO `Directory` (`Directory`, `Directory_Parent`, `DefaultDir`) VALUES ('TARGETDIR',NULL,'SourceDir')",
        L"CREATE TABLE `Feature` (`Feature` CHAR(38) NOT NULL, `Feature_Parent` CHAR(38), `Title` CHAR(64) LOCALIZABLE, `Description` CHAR(255) LOCALIZABLE, `Display` SHORT, `Level` SHORT NOT NULL, `Directory_` CHAR(72), `Attributes` SHORT NOT NULL PRIMARY KEY `Feature`)",
        L"INSERT INTO `Feature` (`Feature`, `Feature_Parent`, `Title`, `Description`, `Display`, `Level`, `Directory_`, `Attributes`) VALUES ('Main',NULL,'Fixture','Private registry fixture',1,1,'TARGETDIR',0)",
        L"CREATE TABLE `Component` (`Component` CHAR(72) NOT NULL, `ComponentId` CHAR(38), `Directory_` CHAR(72) NOT NULL, `Attributes` SHORT NOT NULL, `Condition` CHAR(255), `KeyPath` CHAR(72) PRIMARY KEY `Component`)",
        L"INSERT INTO `Component` (`Component`, `ComponentId`, `Directory_`, `Attributes`, `Condition`, `KeyPath`) VALUES ('Probe','{8C762F94-12D8-42DD-9AAB-12C101330103}','TARGETDIR',260,NULL,'Marker')",
        L"CREATE TABLE `FeatureComponents` (`Feature_` CHAR(38) NOT NULL, `Component_` CHAR(72) NOT NULL PRIMARY KEY `Feature_`, `Component_`)",
        L"INSERT INTO `FeatureComponents` (`Feature_`, `Component_`) VALUES ('Main','Probe')",
        L"CREATE TABLE `Registry` (`Registry` CHAR(72) NOT NULL, `Root` SHORT NOT NULL, `Key` CHAR(255) NOT NULL LOCALIZABLE, `Name` CHAR(255) LOCALIZABLE, `Value` CHAR(0) LOCALIZABLE, `Component_` CHAR(72) NOT NULL PRIMARY KEY `Registry`)",
        L"INSERT INTO `Registry` (`Registry`, `Root`, `Key`, `Name`, `Value`, `Component_`) VALUES ('Marker',1,'Software\\Chardonnay\\InstallerProbe','MSI','passed','Probe')",
        L"CREATE TABLE `InstallExecuteSequence` (`Action` CHAR(72) NOT NULL, `Condition` CHAR(255), `Sequence` SHORT PRIMARY KEY `Action`)",
        L"INSERT INTO `InstallExecuteSequence` (`Action`, `Condition`, `Sequence`) VALUES ('CostInitialize',NULL,800)",
        L"INSERT INTO `InstallExecuteSequence` (`Action`, `Condition`, `Sequence`) VALUES ('FileCost',NULL,900)",
        L"INSERT INTO `InstallExecuteSequence` (`Action`, `Condition`, `Sequence`) VALUES ('CostFinalize',NULL,1000)",
        L"INSERT INTO `InstallExecuteSequence` (`Action`, `Condition`, `Sequence`) VALUES ('InstallValidate',NULL,1400)",
        L"INSERT INTO `InstallExecuteSequence` (`Action`, `Condition`, `Sequence`) VALUES ('InstallInitialize',NULL,1500)",
        L"INSERT INTO `InstallExecuteSequence` (`Action`, `Condition`, `Sequence`) VALUES ('ProcessComponents',NULL,1600)",
        L"INSERT INTO `InstallExecuteSequence` (`Action`, `Condition`, `Sequence`) VALUES ('RemoveRegistryValues',NULL,2600)",
        L"INSERT INTO `InstallExecuteSequence` (`Action`, `Condition`, `Sequence`) VALUES ('WriteRegistryValues',NULL,5000)",
        L"INSERT INTO `InstallExecuteSequence` (`Action`, `Condition`, `Sequence`) VALUES ('RegisterUser',NULL,6000)",
        L"INSERT INTO `InstallExecuteSequence` (`Action`, `Condition`, `Sequence`) VALUES ('RegisterProduct',NULL,6100)",
        L"INSERT INTO `InstallExecuteSequence` (`Action`, `Condition`, `Sequence`) VALUES ('PublishFeatures',NULL,6300)",
        L"INSERT INTO `InstallExecuteSequence` (`Action`, `Condition`, `Sequence`) VALUES ('PublishProduct',NULL,6400)",
        L"INSERT INTO `InstallExecuteSequence` (`Action`, `Condition`, `Sequence`) VALUES ('InstallFinalize',NULL,6600)"
    };
    for(size_t i=0;i<sizeof(statements)/sizeof(statements[0]);i++)if(sql(db,statements[i])){MsiCloseHandle(db);return 3;}
    result=MsiGetSummaryInformationW(db,NULL,8,&summary);
    if(!result)result=MsiSummaryInfoSetPropertyW(summary,7,VT_LPSTR,0,NULL,L"x64;1033");
    if(!result)result=MsiSummaryInfoSetPropertyW(summary,9,VT_LPSTR,0,NULL,L"{8C762F94-12D8-42DD-9AAB-12C101330104}");
    if(!result)result=MsiSummaryInfoSetPropertyW(summary,14,VT_I4,200,NULL,NULL);
    if(!result)result=MsiSummaryInfoSetPropertyW(summary,15,VT_I4,0,NULL,NULL);
    if(!result)result=MsiSummaryInfoPersist(summary);
    if(summary)MsiCloseHandle(summary);
    if(!result)result=MsiDatabaseCommit(db);
    MsiCloseHandle(db);
    FILE *log=fopen("C:\\ChardonnayFixture-msi-build.txt","a");
    if(log){fprintf(log,"summary_result=%u\n",result);fclose(log);}
    return (int)result;
}
