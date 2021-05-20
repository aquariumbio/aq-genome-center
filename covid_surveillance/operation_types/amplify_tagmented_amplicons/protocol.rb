# typed: false
# frozen_string_literal: true

needs 'Standard Libs/PlanParams'
needs 'Standard Libs/Debug'
needs 'Standard Libs/InstrumentHelper'
needs 'Standard Libs/ItemActions'
needs 'Standard Libs/UploadHelper'
needs 'Small Instruments/Centrifuges'
needs 'Small Instruments/Shakers'
needs 'Standard Libs/Units'
needs 'Covid Surveillance/SampleConstants'
needs 'Covid Surveillance/AssociationKeys'
needs 'Covid Surveillance/CovidSurveillanceHelper'
needs 'Liquid Robot Helper/RobotHelper'

needs 'Composition Libs/Composition'
needs 'Composition Libs/CompositionHelper'

needs 'Collection Management/CollectionTransfer'
needs 'Collection Management/CollectionActions'

needs 'PCR Protocols/RunThermocycler'

needs 'Kits/KitContents'

needs 'Consumable Libs/Consumables'
needs 'Consumable Libs/ConsumableDefinitions'

class Protocol
  include PlanParams
  include Debug
  include InstrumentHelper
  include ItemActions
  include UploadHelper
  include Centrifuges
  include Shakers
  include Units
  include SampleConstants
  include AssociationKeys
  include RobotHelper
  include CompositionHelper
  include CollectionTransfer
  include CollectionActions
  include RunThermocycler
  include CovidSurveillanceHelper
  include KitContents
  include ConsumableDefinitions

 #========== Composition Definitions ==========#
  AMP_TAG_KIT = 'Amplify Tagmented Amplicons Kit'
  IDT_PLATE = 'Index Adapter'
  SPARE_PLATE = '96 Well Plate'

  WORKFLOW_NAME = 'GenerateFASTQ'
  APPLICATION_NAME = 'NovaSeqFASTQOnly'
  INSTRUMENTTYPE = 'NovaSeq'
  ASSAY_NAME = 'TruSeqNanoDNA'

  POOLED_PLATE = 'TAG Sample Plate'

  def components
    [ 
       {
         input_name: POOLED_PLATE,
         qty: nil, units: MICROLITERS,
         sample_name: 'Pooled Specimens',
         suggested_ot: PLATE_384_WELL
       },
       {
         input_name: WATER,
         qty: 6, units: MICROLITERS,
         sample_name: WATER,
         suggested_ot: 'Reagent Bottle'
      },
      {
        input_name: MASTER_MIX,
        qty: 20, units: MICROLITERS,
        sample_name: MASTER_MIX,
        suggested_ot: TEST_TUBE
      },
      {
        input_name: IDT_PLATE,
        qty: 10, units: MICROLITERS,
        sample_name: IDT_PLATE,
        suggested_ot: PLATE_384_WELL
      }
    ]
  end

  def consumable_data
    [
      {
        consumable: CONSUMABLES[AREA_SEAL],
        qty: 1, units: 'Each'
      },
      {
        consumable: CONSUMABLES[PLATE_384_WELL],
        qty: 1, units: 'Each'
      },
      {
        consumable: CONSUMABLES[TEST_TUBE],
        qty: 1, units: 'Tubes'
      }
    ]
  end

########## DEFAULT PARAMS ##########

# Default parameters that are applied equally to all operations.
#   Can be overridden by:
#   * Associating a JSON-formatted list of key, value pairs to the `Plan`.
#   * Adding a JSON-formatted list of key, value pairs to an `Operation`
#     input of type JSON and named `Options`.
#
def default_job_params
  {
  }
end

# Default parameters that are applied to individual operations.
#   Can be overridden by:
#   * Adding a JSON-formatted list of key, value pairs to an `Operation`
#     input of type JSON and named `Options`.
#
def default_operation_params
  {
    mosquito_remove_robot_program: 'Amplify Tagmented Amplicons',
    transfer_index_program: 'Amplify Tagmented Amplicons Index Plate',
    mosquito_transfer_index_program: 'PCR_MM',
    mosquito_robot_model: Mosquito::MODEL,
    dragonfly_robot_program: 'EP3_HT',
    dragonfly_robot_model: Dragonfly::MODEL,
    storage_location: 'M80',
    shaker_parameters: { time: create_qty(qty: 1, units: MINUTES),
                         speed: create_qty(qty: 1600, units: RPM) },
    centrifuge_parameters: { time: create_qty(qty: 1, units: MINUTES),
                             speed: create_qty(qty: 500, units: TIMES_G) },
    incubation_params: { time: create_qty(qty: 5, units: MINUTES),
                         temperature: create_qty(qty: 'room temperature',
                                                 units: '') },
    thermocycler_model: TestThermocycler::MODEL,
    program_name: 'duke_amplify_tagmenteed_amplicons',
    qpcr: true
  }
end

  ########## MAIN ##########

  def main
    @job_params = update_all_params(
      operations: operations,
      default_job_params: default_job_params,
      default_operation_params: default_operation_params
    )

    operations.each do |op|
      set_up_test(op) if debug
      op.pass(POOLED_PLATE)

      temporary_options = op.temporary[:options]


      composition, consumables, _kit_ = setup_kit_composition(
        kit_sample_names: [AMP_TAG_KIT],
        num_reactions_required: op.input(POOLED_PLATE).collection.parts.length,
        components: components,
        consumables: consumable_data
      )

      composition.input(POOLED_PLATE).item = op.input(POOLED_PLATE).collection
      composition.input(IDT_PLATE).item = op.input(IDT_PLATE).collection

      plate = composition.input(POOLED_PLATE).item
      composition.input(WATER).item = find_random_item(
        sample: composition.input(WATER).sample,
        object_type: composition.input(WATER).suggested_ot
      )

      mm = composition.input(MASTER_MIX)
      adj_multi = plate.get_non_empty.length
      mm_components = [composition.input(EPM_HT),
                       composition.input(WATER)]

      composition.set_adj_qty(plate.get_non_empty.length, extra: 0.005)

      mm.item = make_item(sample: mm.sample,
                          object_type: mm.suggested_ot)

      retrieve_list = reject_components(
        list_of_rejections: [MASTER_MIX, POOLED_PLATE],
        components: composition.components
      )

      display(
        title: 'Retrieve Materials',
        show_block: [retrieve_materials(retrieve_list + consumables.consumables,
                                        adj_qty: true)]
      )

      vortex_list = reject_components(
        list_of_rejections: [WATER, IDT_PLATE],
        components: retrieve_list
      )
      show_block_1 = []
      show_block_1.append(
        { display: shake(items: vortex_list.map(&:display_name),
                         type: Vortex::NAME),
          type: 'note' }
      )


      mm_components = [composition.input(EPM_HT), composition.input(WATER)]

      show_block_1.append({
        display: master_mix_handler(components: mm_components,
                                    mm: composition.input(MASTER_MIX),
                                    mm_container: composition.input(TEST_TUBE)),
        type: 'note'
      })

      show_block_1.append({ display: place_on_magnet(composition.input(POOLED_PLATE)), type: 'note' })

      mosquito_robot = LiquidRobotFactory.build(
        model: temporary_options[:mosquito_robot_model],
        name: op.temporary[:robot_model],
        protocol: self
      )

      drgrobot = LiquidRobotFactory.build(
        model: temporary_options[:dragonfly_robot_model],
        name: op.temporary[:robot_model],
        protocol: self
      )

      remove_supernatant_program = LiquidRobotProgramFactory.build(
        program_name: temporary_options[:mosquito_remove_robot_program]
      )

      show_block_1.append(
        use_robot(program: remove_supernatant_program,
                  robot: mosquito_robot,
                  items: [composition.input(POOLED_PLATE).display_name])
      )

      add_mm_program = LiquidRobotProgramFactory.build(
        program_name: temporary_options[:dragonfly_robot_program]
      )

      show_block_1.append(
        use_robot(program: add_mm_program,
                  robot: drgrobot,
                  items: [composition.input(POOLED_PLATE).display_name,
                          composition.input(MASTER_MIX).display_name])
      )

      use_rbt = use_robot(program: remove_supernatant_program,
                          robot: mosquito_robot,
                          items: [composition.input(POOLED_PLATE).display_name,
                                  composition.input(IDT_PLATE)])

      use_rbt[1] = { display: "Continue with the <b>#{remove_supernatant_program.program_template_name}</b> protocol", type: 'note' }

      show_block_1.append(
        use_rbt
      )

      display_hash(
        title: 'Prep and Run Robot',
        hash_to_show: show_block_1
      )

      association_map = one_to_one_association_map(from_collection: plate)

      associate_transfer_item_to_collection(
        from_item: mm.item,
        to_collection: plate,
        association_map: association_map,
        transfer_vol: mm.volume_hash
      )

      associate_transfer_collection_to_collection(
        from_collection: composition.input(IDT_PLATE).item,
        to_collection: plate,
        association_map: association_map,
        transfer_vol: composition.input(IDT_PLATE).volume_hash
      )

      transfer_adapter_index(from_plate: composition.input(IDT_PLATE).item,
                             to_plate: plate)

      show_block_2 = []
      show_block_2.append(
        {
          display: seal_plate(
            [composition.input(POOLED_PLATE).display_name],
            seal: consumables.input(AREA_SEAL)
          ),
          type: 'note'
        }
      )

      show_block_2.append(
        {
          display: shake(
            items: [composition.input(POOLED_PLATE).display_name],
            speed: temporary_options[:shaker_parameters][:speed],
            time: temporary_options[:shaker_parameters][:time]
          ),
          type: 'note'
        }
      )

      show_block_2.append(
        {
          display: spin_down(
            items: [composition.input(POOLED_PLATE).display_name],
            speed: temporary_options[:centrifuge_parameters][:speed],
            time: temporary_options[:centrifuge_parameters][:time]
          ),
          type: 'note'
        }
      )

      show_block_2.append(
        {
          display: 'Ensure beads are resuspend',
          type: 'note'
        }
      )

      display_hash(
        title: 'Prepare for Thermocycler',
        hash_to_show: show_block_2
      )

      run_qpcr(op: op,
               plates: [composition.input(POOLED_PLATE).item])

      generate_csv(composition.input(POOLED_PLATE).item, op)
    end

    {}

  end

  def generate_csv(plate, op)
    csv_arrays = [
      ['[Header]'],
      [],
      ['IEMFileVersion', 5],
      [],
      ['Date', Time.new.strftime("%m/%d/%Y")],
      [],
      ['Workflow', WORKFLOW_NAME],
      [],
      ['Application', APPLICATION_NAME],
      [],
      ['InstrumentType', INSTRUMENTTYPE],
      [],
      ['Assay', ASSAY_NAME],
      [],
      ['IndexAdapters'],
      [],
      ['Description'],
      [],
      ['Chemsitry'],
      [],
      [],
      [],
      ['[Reads]'],
      [],
      [151],
      [],
      [151],
      [],
      [],
      [],
      ['[Settings]'],
      [],
      [],
      [],
      [],
      [],
      [],
      [],
      ['[Data]'],
      ['Lane', 'Sample_ID', 'Sample_Name', 'Sample_Plate', 'Sample_Well',
       'i7_Index_ID', 'index', 'i5_Index_ID', 'index2',
       'Sample_Project', 'Description']
    ]
    plate.parts.each do |well|
      csv_arrays.push([])
      csv_arrays.push(
        [nil, well.sample.name,nil,nil,nil,nil,
         well.get(INDEX_KEY),nil,nil,nil,nil]
      )
    end
    output_csv = CSV.new(csv_arrays.to_csv)
    inspect output_csv if debug
    up = Upload.new
    up.upload = StringIO.new(csv_arrays.to_s)
    up.name = RNA_EXTRACTION_DATA + op.id.to_s
    up.save

    op.associate(RNA_EXTRACTION_DATA, up)
  end

  def transfer_adapter_index(from_plate:, to_plate:)
    from_plate.get_non_empty.each do |r, c|
      to_part = to_plate.part(r, c)
      from_part = from_plate.part(r, c)
      next if to_part.nil? || from_part.nil?

      to_part.associate(INDEX_KEY, from_part.sample.name.to_s)
    end
  end

  def set_up_test(op)
    sample = op.input(POOLED_PLATE).part.sample
    plate = op.input(POOLED_PLATE).collection
    samples = Array.new(plate.get_empty.length, sample)
    plate.add_samples(samples)

    sample = op.input(IDT_PLATE).part.sample
    plate = op.input(IDT_PLATE).collection
    samples = Array.new(plate.get_empty.length, sample)
    plate.add_samples(samples)
  end

end