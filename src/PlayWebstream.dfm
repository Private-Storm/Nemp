object FPlayWebstream: TFPlayWebstream
  Left = 0
  Top = 0
  BorderStyle = bsDialog
  Caption = 'Nemp: Play webstream'
  ClientHeight = 95
  ClientWidth = 430
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'Tahoma'
  Font.Style = []
  OldCreateOrder = False
  Position = poOwnerFormCenter
  OnCreate = FormCreate
  DesignSize = (
    430
    95)
  PixelsPerInch = 96
  TextHeight = 13
  object lblURL: TLabel
    Left = 8
    Top = 8
    Width = 354
    Height = 13
    Anchors = [akLeft, akTop, akRight]
    Caption = 
      'URL (e.g. "http://myhits.com/tune_in.pls" or "http://123.12.34.5' +
      '6:5000")'
  end
  object BtnCancel: TButton
    AlignWithMargins = True
    Left = 319
    Top = 62
    Width = 97
    Height = 25
    Cancel = True
    Caption = 'Cancel'
    ModalResult = 2
    TabOrder = 0
  end
  object BtnOK: TButton
    AlignWithMargins = True
    Left = 216
    Top = 62
    Width = 97
    Height = 25
    Caption = 'Ok'
    Default = True
    ModalResult = 1
    TabOrder = 1
  end
  object BtnFavorites: TButton
    AlignWithMargins = True
    Left = 8
    Top = 62
    Width = 97
    Height = 25
    Caption = 'Favorites'
    ModalResult = 4
    TabOrder = 2
  end
  object edtURL: TEdit
    AlignWithMargins = True
    Left = 8
    Top = 27
    Width = 408
    Height = 21
    Anchors = [akLeft, akTop, akRight]
    TabOrder = 3
    Text = 'http://'
    ExplicitWidth = 414
  end
end
