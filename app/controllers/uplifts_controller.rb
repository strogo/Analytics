require 'nokogiri'
require 'csv'

class UpliftsController < ApplicationController
  skip_before_filter  :verify_authenticity_token
  before_filter :current_user!

  attr_accessor :uplift_file

  def uplift
    startime = DateTime.now
    eid = params[:eid]
    @election = Election.find(eid) unless defined?(@election)
    @uplift_msg = ""
    @uplift_err = ""
    @uplift_csv = ""
    unless params['file']
      @uplift_msg = "Error: choose file name"
      render :uplift
      return
    end
    self.uplift_file = params['file'].original_filename
    uploader = LogfileUploader.new
    post = uploader.store!( params['file'] )
    @uplift_msg = "Uploaded: " + self.uplift_file
    if (params[:uptype] == "vr")
      self.upliftVoterRecords("public/uploads/"+self.uplift_file, eid)
    else
      self.upliftValidate("public/uploads/"+self.uplift_file, eid)
    end
  rescue CarrierWave::IntegrityError => e
    @uplift_msg = "Invalid XML file name: "+self.uplift_file
    render :uplift
  rescue => e
    @uplift_msg = "Shouldn't happen #1: "+e.message # JVC temp
    render :uplift
  end

  def upliftDuration(t1, t2)
    return " ("+t1.to_s+" | "+t2.to_s+")"
    return distance_of_time_in_words(t1, to_time=t2, include_seconds=true)
  end
  
  def upliftReadXMLSchema(file)
    return Nokogiri::XML::Schema(File.read(file))
  rescue => e
    @uplift_err += " Shouldn't happen #3, invalid built-in schema. "+e.message
    render :uplift
    return false
  end
  
  def upliftReadXMLDocument(file)
    return Nokogiri::XML(File.open(file))
  rescue => e
    @uplift_err += "Invalid File format: "+e.message
    render :uplift
    return false
  end

  def upliftValidate(document_path, eid)
    return unless (schema = self.upliftReadXMLSchema("public/schemas/VTL.xsd"))
    return unless (document = self.upliftReadXMLDocument(document_path))
    errors = schema.validate(document)
    if (errors.length > 0)
      @uplift_err += "Validation Errors: "      
      errors.each { |e| @uplift_err += e.message }
      if @uplift_err =~ / root\.$/
        errs = @uplift_err.split(' ')
        errs.pop
        errs = errs.push("root <voterTransactionLog>")
        @uplift_err = errs.join(' ')
      end
      render :uplift
    else
      if self.upliftFinalizeLog(document, eid)
        if (@uplift_err == "")
          @uplift_err = "Validation: OK"
        end
        redirect_to '/elections/'+eid.to_s, {:params=>{:id=>eid}}
      else
        render :uplift
      end
    end
  rescue => e
    @uplift_err += " Should't happen #2: "+e.message # JVC temp
  end

  def upliftExtractContent(xml)
    return (xml ? xml.content : "")
  end

  def upliftMungeForm(type1, type2, name, number)
    if type1.blank?
      return ""
    elsif type2.blank?
      if name.blank? and number.blank?
        return type1
      else
        return type1+" | "+(name.blank? ? " | " : " | "+name)+
          (number.blank? ? "" : " | "+number)
      end
    elsif name.blank? and number.blank?
      return type1+" | "+type2
    else
      return type1+" | "+type2+(name.blank? ? " | " : " | "+name)+
        (number.blank? ? "" : " | "+number)
    end
  end

  # def updateVoterFieldsFromRecord(vr)
  #   if v = Voter.where(:vname=>vr.vname).first
  #     unless (v.vgender==vr.gender && v.vparty==vr.party &&
  #             v.vother==vr.other && v.vstatus==vr.status)
  #       v.vgender = vr.gender
  #       v.vparty = vr.party
  #       v.vother = vr.other
  #       v.vstatus = (vr.absentee=~/Y/ ? 'absentee' : '')
  #       e = Election.find(v.election_id)
  #       v.vnew = vr.new?(e)
  #       v.save
  #     end
  #   end
  # end

  # def syncVoter(voter, vtr)
  #   if (vtr.form =~ /PollBook/)
  #     voter.votes += 1
  #     voter.vote_reject = false
  #     voter.vote_form = "Regular"
  #   elsif (vtr.form =~ /AbsenteeBallot/)
  #     if (vtr.action == 'approve')
  #       voter.votes += 1
  #       voter.vote_reject = false
  #       voter.vote_form = "Absentee"
  #     elsif (vtr.action == 'reject')
  #       voter.votes += 1
  #       voter.vote_reject = true
  #       voter.vote_note = vtr.note
  #       voter.vote_form = "Absentee"
  #     end
  #   elsif (vtr.form =~ /ProvisionalBallot/)
  #     if (vtr.action == 'approve')
  #       voter.votes += 1
  #       voter.vote_reject = false
  #       voter.vote_form = "Provisional"
  #     elsif (vtr.action == 'reject')
  #       voter.votes += 1
  #       voter.vote_reject = true
  #       voter.vote_note = vtr.note
  #       voter.vote_form = "Provisional"
  #     end
  #   elsif (vtr.form =~ /VoterRegistration/)
  #     if (vtr.action == 'approve')
  #       voter.vregister = 'approve'
  #     elsif (vtr.action == 'reject')
  #       voter.vregister = 'reject'
  #     else
  #       voter.vregister = 'try' unless voter.vregister == 'approve'
  #     end
  #   elsif (vtr.form =~ /RecordUpdate/)
  #     if (vtr.action == 'approve')
  #       voter.vupdate = 'approve'
  #     elsif (vtr.action == 'reject')
  #       voter.vupdate = 'reject'
  #     else
  #       voter.vupdate = 'try' unless voter.vupdate == 'approve'
  #     end
  #   elsif (vtr.form =~ /AbsenteeRequest/)
  #     if (vtr.action == 'approve')
  #       voter.vabsreq = 'approve'
  #     elsif (vtr.action == 'reject')
  #       voter.vabsreq = 'reject'
  #     else
  #       voter.vabsreq = 'try' unless voter.vabsreq == 'approve'
  #     end
  #   end
  #   if ["identify","start","discard","complete","submit"].include?(vtr.action)
  #     voter.vonline = true
  #   end
  #   voter.vtr_state_push()
  #   voter.save
  # end

  def upliftFinalizeLog(xml, eid)
    origin = self.upliftExtractContent(xml % 'header/origin')
    ouniq = self.upliftExtractContent(xml % 'header/originUniq')
    logdate = self.upliftExtractContent(xml % 'header/createDate')
    vtl = VoterTransactionLog.new(:origin => origin,
                                  :origin_uniq => ouniq,
                                  :datime => logdate,
                                  :file_name => self.uplift_file,
                                  :archive_name => '',
                                  :election_id => eid)
    unless (vtl.save)
      @uplift_err = "Error: "
      vtl.errors.full_messages.each { |e| @uplift_err += " "+e }
      return false
    end
    (xml / 'voterTransactionRecord').each do |vtr|
      vname = self.upliftExtractContent(vtr % 'voterid')
      datime = self.upliftExtractContent(vtr % 'date')
      action = self.upliftExtractContent(vtr % 'action')
      form = self.upliftExtractContent(vtr % 'form')+" "+
        self.upliftExtractContent(vtr % 'formNote')
      leo = self.upliftExtractContent(vtr % 'leo')
      note = self.upliftExtractContent(vtr % 'notes')
      comment = self.upliftExtractContent(vtr % 'comment')
      # voter = self.upliftVoter(vname, eid)
      # unless (voter.save)
      #   voter.errors.full_messages.each { |e| @uplift_err += " "+e }
      #   return false
      # end
      # vid = voter.id
      vtr = VoterTransactionRecord.new(:datime => datime,
                                       :vname => vname,
                                       :action => action,
                                       :form => form,
                                       :leo => leo,
                                       :note => note,
                                       :comment => comment,
                                       :voter_transaction_log_id => vtl.id)
                                       #:voter_id => vid)
      unless (vtr.save)
        vtl.errors.full_messages.each { |e| @uplift_err += " "+e }
        return false
      end
      #JVC too early self.syncVoter(voter, vtr)
    end
    vtl.create_archive_file
    vtl.save
    return true
  end

  # http://vitobotta.com/more-methods-format-beautify-ruby-output-console-logs/

  def upliftXMLpp(xml_text)
    xsl = <<XSL
  <xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
    <xsl:output method="xml" encoding="UTF-8" indent="yes"/>
    <xsl:strip-space elements="*"/>
    <xsl:template match="/">
      <xsl:copy-of select="."/>
    </xsl:template>
  </xsl:stylesheet>

XSL

    doc  = Nokogiri::XML(xml_text)
    xslt = Nokogiri::XSLT(xsl)
    out  = xslt.transform(doc)
    puts out.to_xml
  end

  def upliftVoterRecords(csv_file, eid)
    unless (csv_file =~ /\.csv$/i)
      @uplift_err = "Invalid file type, only .CSV files accepted: "+csv_file.to_s
      render :uplift
      return false
    end
    if self.csv_import(csv_file)
      voter_records_file_new('public/uploads/',self.uplift_file)
      redirect_to '/voter_records', {:params=>{:id=>eid}}
      return true
    end
  end

  def csv_import(file)
    unless csv = IO.readlines(file)
      @uplift_err = "File not readable: "+file
      render :uplift
      return false
    end
    unless true or csv[0] =~ /^Voter,Type,Gender,Party/ #JVC
      @uplift_err = "Invalid header line of CSV file: "+csv[0]
      render :uplift
      return false
    end
    avhash = voter_record_report_init()
    vrhash = Hash.new {}
    csv.shift
    csv.each do |row| # JVC row.split needs to check the data
      (vname, gender, party, military, overseas, abs, rdate) = row.split(',')
      vr=VoterRecord.new(:vname=>vname, :gender=>gender,
                         :party=>party, :military=>military, :other=>'',
                         :overseas=>overseas, :absentee=>abs, :regidate=>rdate)
      vr.other += 'M' if military=~/Y/
      vr.other += 'O' if overseas=~/Y/
      vr.status = (abs=~/Y/ ? 'absentee' : '')
      new = vr.new?(@election)
      vrhash[vr.vname] = [vr.gender, vr.party, vr.other, vr.status, new]
      vr.save
      voter_record_report_update(avhash, vr, @election)
    end
    voter_record_report_finalize(avhash)
    voter_record_report_save(avhash, @election)
    # Voter.all.each do |v|
    #   if vrhash.keys.include?(v.vname)
    #     gender, party, other, status, new = vrhash[v.vname]
    #     if (v.vgender != gender || v.vparty != party ||
    #         v.vother != other || v.vstatus != status ||
    #         v.vnew != new)
    #       v.vgender, v.vparty, v.vother, v.vstatus = gender, party, other, status
    #       v.vnew = new
    #       v.save
    #     end
    #   end
    # end
    return true
  end

  def voter_records_file_new (fupath, file)
    path = 'public/records'
    unless File.directory?(path) || FileUtils.mkdir(path)
      raise Exception, "No voter records repository: "+path
    end
    files = Array.new
    Dir.new(path).entries.each do |f|
      if f =~ /\.csv$/i
        unless File.delete(path+"/"+f)
          raise Exception, "Cannot delete old voter records file: "+f
        end
      end
    end
    FileUtils.copy(fupath+"/"+file, path+"/"+file)
    unless File.exists?(path+"/"+file)
      raise Exception, "Cannot store voter records file: "+file
    end
  end

end
