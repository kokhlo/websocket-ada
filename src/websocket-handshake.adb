-- RFC 6455 opening handshake implementation (§4.1, §4.2.2)
with Ada.Streams;
with Ada.Strings.Fixed;
with Ada.Numerics.Discrete_Random;
with GNAT.SHA1;
with Websocket.Base64;

package body Websocket.Handshake is

   -------------------------------------------------------------------
   -- Case-insensitive ASCII comparison (HTTP header names and values
   -- such as "websocket" arrive in any casing; RFC 7230 §3.2)
   -------------------------------------------------------------------
   function To_Lower (C : Character) return Character is
      (if C in 'A' .. 'Z'
       then Character'Val (Character'Pos (C) + 32)
       else C);

   function Equal_Ignore_Case (A, B : String) return Boolean is
   begin
      if A'Length /= B'Length then
         return False;
      end if;
      for I in 0 .. A'Length - 1 loop
         if To_Lower (A (A'First + I)) /= To_Lower (B (B'First + I)) then
            return False;
         end if;
      end loop;
      return True;
   end Equal_Ignore_Case;

   -- True when Token occurs in the comma-separated Value string
   -- (Connection: keep-alive, Upgrade — RFC 7230 §6.1 token list).
   -- Whitespace around commas is ignored.
   function Contains_Token (Value : String; Token : String) return Boolean is
      use Ada.Strings.Fixed;
      Start : Positive := Value'First;
      Comma_Pos : Natural;
   begin
      loop
         -- Skip leading spaces
         while Start <= Value'Last and then Value (Start) = ' ' loop
            Start := Start + 1;
         end loop;
         exit when Start > Value'Last;

         Comma_Pos := Index (Value (Start .. Value'Last), ",");
         if Comma_Pos = 0 then
            -- Last token in the list
            declare
               Segment : constant String :=
                  Trim (Value (Start .. Value'Last), Ada.Strings.Both);
            begin
               return Equal_Ignore_Case (Segment, Token);
            end;
         end if;

         declare
            Segment : constant String :=
               Trim (Value (Start .. Comma_Pos - 1), Ada.Strings.Both);
         begin
            if Equal_Ignore_Case (Segment, Token) then
               return True;
            end if;
         end;

         Start := Comma_Pos + 1;
      end loop;
      return False;
   end Contains_Token;

   -------------------------------------------------------------------
   -- Build_Client_Request: full HTTP GET upgrade request (RFC 6455 §4.1)
   -------------------------------------------------------------------
   function Build_Client_Request
      (Host : String;
       Port : Natural;
       Path : String;
       Random_Key : String)
      return String
   is
      use Ada.Strings.Fixed;
      Host_Header : constant String :=
         (if Port = 80 or else Port = 443
          then Host
          else Host & ":" & Trim (Natural'Image (Port), Ada.Strings.Both));
   begin
      return
         "GET " & Path & " HTTP/1.1" & ASCII.CR & ASCII.LF &
         "Host: " & Host_Header & ASCII.CR & ASCII.LF &
         "Upgrade: websocket" & ASCII.CR & ASCII.LF &
         "Connection: Upgrade" & ASCII.CR & ASCII.LF &
         "Sec-WebSocket-Key: " & Random_Key & ASCII.CR & ASCII.LF &
         "Sec-WebSocket-Version: 13" & ASCII.CR & ASCII.LF &
         ASCII.CR & ASCII.LF;
   end Build_Client_Request;

   -------------------------------------------------------------------
   -- Compute_Accept: base64(SHA1(key + magic)) (RFC 6455 §4.2.2)
   -- The RFC's official example: key "dGhlIHNhbXBsZSBub25jZQ==" must
   -- produce "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=".
   -------------------------------------------------------------------
   function Compute_Accept (Key : String) return String is
      Digest : constant GNAT.SHA1.Binary_Message_Digest :=
         GNAT.SHA1.Digest (Key & WS_Magic_String);
   begin
      return Base64.Encode (Digest);
   end Compute_Accept;

   -------------------------------------------------------------------
   -- Generate_Key: 16 random bytes, base64-encoded (RFC 6455 §4.1)
   -------------------------------------------------------------------
   subtype Byte_Value is Ada.Streams.Stream_Element;

   package Byte_Random is new Ada.Numerics.Discrete_Random (Byte_Value);

   function Generate_Key return String is
      Gen : Byte_Random.Generator;
      Bytes : Ada.Streams.Stream_Element_Array (1 .. 16);
   begin
      Byte_Random.Reset (Gen);
      for I in Bytes'Range loop
         Bytes (I) := Byte_Random.Random (Gen);
      end loop;
      return Base64.Encode (Bytes);
   end Generate_Key;

   -------------------------------------------------------------------
   -- Validate_Server_Response: client-side §4.2.2 checks
   -------------------------------------------------------------------
   function Validate_Server_Response
      (Response : String;
       Expected_Accept : String)
      return Status
   is
      use Ada.Strings.Fixed;

      -- Parse the status line: "HTTP/1.1 101 Switching Protocols\r\n"
      function Parse_Status_Line return Status is
         Line_End : constant Natural := Index (Response, ASCII.CR & ASCII.LF);
      begin
         if Line_End = 0 or else Line_End <= Response'First then
            return (Kind => Wrong_Status, Code => 0, Header => Upgrade_Header);
         end if;

         declare
            Line : constant String := Response (Response'First .. Line_End - 1);
            Code_Start : Natural;
            Code_End   : Natural;
         begin
            -- Find the space after "HTTP/1.1"
            Code_Start := Index (Line, " ");
            if Code_Start = 0 then
               return (Kind => Wrong_Status, Code => 0, Header => Upgrade_Header);
            end if;
            Code_Start := Code_Start + 1;

            -- Find the end of the 3-digit code
            Code_End := Index (Line (Code_Start .. Line'Last), " ");
            if Code_End = 0 then
               Code_End := Line'Last + 1;
            end if;
            Code_End := Code_End - 1;

            declare
               Code_Str : constant String := Line (Code_Start .. Code_End);
               Code : Natural;
            begin
               Code := Natural'Value (Code_Str);
               if Code /= 101 then
                  return (Kind => Wrong_Status, Code => Code, Header => Upgrade_Header);
               end if;
            exception
               when Constraint_Error =>
                  return (Kind => Wrong_Status, Code => 0, Header => Upgrade_Header);
            end;
         end;

         return (Kind => OK, Code => 0, Header => Upgrade_Header);
      end Parse_Status_Line;

      -- Find a header value by name (case-insensitive).
      -- Returns the value after the colon, or an empty string if absent.
      function Get_Header (Name : String) return String is
         Line_Start : Positive := Response'First;
         Line_End   : Natural;
      begin
         -- Skip the status line
         Line_End := Index (Response, ASCII.CR & ASCII.LF);
         if Line_End = 0 then
            return "";
         end if;
         Line_Start := Line_End + 2;

         loop
            exit when Line_Start > Response'Last;
            Line_End := Index (Response (Line_Start .. Response'Last), ASCII.CR & ASCII.LF);
            if Line_End = 0 then
               Line_End := Response'Last + 1;
            end if;

            declare
               Line : constant String := Response (Line_Start .. Line_End - 1);
               Colon_Pos : constant Natural := Index (Line, ":");
            begin
               if Colon_Pos > Line'First then
                  declare
                     Header_Name : constant String :=
                        Trim (Line (Line'First .. Colon_Pos - 1), Ada.Strings.Both);
                     Header_Value : constant String :=
                        Trim (Line (Colon_Pos + 1 .. Line'Last), Ada.Strings.Both);
                  begin
                     if Equal_Ignore_Case (Header_Name, Name) then
                        return Header_Value;
                     end if;
                  end;
               end if;
            end;

            Line_Start := Line_End + 2;
         end loop;

         return "";
      end Get_Header;

      Status_Result : constant Status := Parse_Status_Line;
      Upgrade_Value : constant String := Get_Header ("Upgrade");
      Connection_Value : constant String := Get_Header ("Connection");
      Accept_Value : constant String := Get_Header ("Sec-WebSocket-Accept");

   begin
      if Status_Result.Kind /= OK then
         return Status_Result;
      end if;

      -- Check Upgrade: websocket
      if not Equal_Ignore_Case (Upgrade_Value, "websocket") then
         return (Kind => Missing_Header, Code => 0, Header => Upgrade_Header);
      end if;

      -- Check Connection contains "Upgrade" (case-insensitive token search)
      if not Contains_Token (Connection_Value, "Upgrade") then
         return (Kind => Missing_Header, Code => 0, Header => Connection_Header);
      end if;

      -- Check Sec-WebSocket-Accept matches Expected_Accept (exact match)
      if Accept_Value /= Expected_Accept then
         return (Kind => Accept_Mismatch, Code => 0, Header => Accept_Header);
      end if;

      return (Kind => OK, Code => 0, Header => Upgrade_Header);
   end Validate_Server_Response;

end Websocket.Handshake;
