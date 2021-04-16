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

needs 'Kits/KitContents'

needs 'Consumable Libs/Consumables'
needs 'Consumable Libs/ConsumableDefinitions'

needs 'Standard Libs/TestFixtures'
needs 'Standard Libs/TestMetrics'
needs 'Standard Libs/ProvenanceFinder'

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
  include CovidSurveillanceHelper
  include KitContents
  include ConsumableDefinitions
  include TestFixtures
  include TestMetrics
  include ProvenanceFinder

 #========== Composition Definitions ==========#

  COMPOSITION_KEY = 'composition'

  POOLED_LIBRARY = 'Final Pool'
  KIT_SAMPLE_NAME = 'dsDNA HS Assay Kit'

  OUTPUT_LIBRARY = 'Stock Tube'
  DIL_10X = '10X Dil of Stock'
  SEQ_POOL_TUBE = 'Seq. Pool Tube'
  FINAL_DILUTION = 'Final Dilution'


  QBIT_JUICE = 'QBIT Juice'
  DILUTION = '10X Dil'

  S1 = 'S1'
  S2 = 'S2'

  def components
    [
      {
        input_name: POOLED_LIBRARY,
        qty: 10, units: MICROLITERS,
        sample_name: nil,
        suggested_ot: nil
      },
      {
        input_name: MASTER_MIX,
        qty: 180, units: MICROLITERS,
        sample_name: MASTER_MIX,
        suggested_ot: 'Reagent Bottle'
     },
     {
       input_name: WATER,
       qty: nil, units: nil,
       sample_name: WATER,
       suggested_ot: 'Reagent Bottle'
     },
     {
      input_name: OUTPUT_LIBRARY,
      qty: nil, units: nil,
      sample_name: nil,
      suggested_ot: 'Reagent Bottle'
    },
    {
      input_name: DIL_10X,
      qty: nil, units: nil,
      sample_name: nil,
      suggested_ot: 'Reagent Bottle'
    },
    {
      input_name: SEQ_POOL_TUBE,
      qty: nil, units: nil,
      sample_name: nil,
      suggested_ot: 'Reagent Bottle'
    },
    {
      input_name: FINAL_DILUTION,
      qty: nil, units: nil,
      sample_name: nil,
      suggested_ot: 'Reagent Bottle'
    }
   ]
  end

  def consumable_data
    [
      {
        consumable: CONSUMABLES[STRIP_TUBE8],
        qty: 1, units: 'Each'
      },
      {
        consumable: CONSUMABLES[MICRO_TUBE],
        qty: 2, units: 'Each'
      },
      {
        consumable: CONSUMABLES[TUBE_5ML],
        qty: 1, units: 'Each'
      }
    ]
  end

########## DEFAULT PARAMS ##########

# Default parameters that are applied equally to all operations.
#   Can be overridden by:
#   * Associating a JSON-formatted list of key, value pairs to the `Plan`.
#   * Adding a JSON-formatted list of key, value pairs to an `Operation`
#     input of type JSON and named `Options`.
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
    shaker_parameters: { time: create_qty(qty: 1, units: MINUTES),
                         speed: create_qty(qty: 1600, units: RPM) },
    centrifuge_parameters: { time: create_qty(qty: 1, units: MINUTES),
                             speed: create_qty(qty: 500, units: TIMES_G) },
    incubation_params: { time: create_qty(qty: 5, units: MINUTES),
                         temperature: create_qty(qty: 'room temperature',
                                                 units: '') }
  }
end

  ########## MAIN ##########

  def main
    target_volume = 35 # ul
    target_molarity = 4 # nM
    @job_params = update_all_params(
      operations: operations,
      default_job_params: default_job_params,
      default_operation_params: default_operation_params
    )

    required_reactions = operations.length + 2

    operations.make

    retrieve_list = []

    operations.each_with_index do |op, idx|
      composition, consumables, _kit_ = setup_kit_composition(
        kit_sample_names: [KIT_SAMPLE_NAME],
        num_reactions_required: create_qty(qty:required_reactions, units: 'rxn'),
        components: components,
        consumables: consumable_data
      )

      composition.input(OUTPUT_LIBRARY).item = op.output(OUTPUT_LIBRARY).item
      composition.input(SEQ_POOL_TUBE).item = op.output(SEQ_POOL_TUBE).item
      composition.input(DIL_10X).item = op.output(DIL_10X).item
      composition.input(FINAL_DILUTION).item = op.output(FINAL_DILUTION).item

      composition.input(WATER).item = find_random_item(
        sample: composition.input(WATER).sample,
        object_type: composition.input(WATER).suggested_ot
      )

      composition.input(POOLED_LIBRARY).item = op.input(POOLED_LIBRARY).item

      adj_vol_list = reject_components(
        list_of_rejections: [POOLED_LIBRARY, MASTER_MIX, OUTPUT_LIBRARY, DIL_10X, SEQ_POOL_TUBE, FINAL_DILUTION],
        components: composition.components
      )

      op.temporary[COMPOSITION_KEY] = [composition, consumables]

      adjust_volume(components: adj_vol_list,
                    multi: required_reactions)
      if idx == 0
        retrieve_list += reject_components(
          list_of_rejections: [POOLED_LIBRARY, MASTER_MIX],
          components: composition.components
        )
      end

      retrieve_list.append(composition.input(POOLED_LIBRARY))
      retrieve_list += consumables.consumables

      mm_components = [composition.input(COMP_B),
                       composition.input(COMP_A)]

      show_block_1a = label_items(
        objects: [consumables.input(TUBE_5ML), consumables.input(MICRO_TUBE)],
        labels: [QBIT_JUICE, DILUTION]
      )

      show_block_1b = pipet(
        volume: composition.input(COMP_A).volume_hash,
        source: composition.input(COMP_A),
        destination: QBIT_JUICE
      )

      show_block_1c = pipet(
        volume: composition.input(COMP_D).volume_hash,
        source: composition.input(COMP_D),
        destination: QBIT_JUICE
      )

      show_block_1d = shake(
        items: [QBIT_JUICE],
        type: Vortex::NAME
      )

      show_block_1e = pipet(
        volume: create_qty(qty: 90, units: MICROLITERS),
        source: composition.input(WATER),
        destination: DILUTION
      )

      show_block_1f = pipet(
        volume: create_qty(qty: 10, units: MICROLITERS),
        source: composition.input(POOLED_LIBRARY),
        destination: DILUTION
      )

      show_retrieve_parts(retrieve_list)

      display_hash(
        title: 'Prepare Items',
        hash_to_show: [
          show_block_1a,
          show_block_1b,
          show_block_1c,
          show_block_1d,
          show_block_1e,
          show_block_1f
        ]
      )

      show_block_2a = label_items(
        objects: [consumables.input(QBIT_TUBE),
                  consumables.input(QBIT_TUBE),
                  consumables.input(QBIT_TUBE),
                  consumables.input(QBIT_TUBE),
                  consumables.input(QBIT_TUBE),
                  consumables.input(QBIT_TUBE)],
        labels: [composition.input(OUTPUT_LIBRARY),
                 S1,
                 S2,
                 composition.input(DIL_10X),
                 composition.input(SEQ_POOL_TUBE),
                 composition.input(FINAL_DILUTION)]
      )

      show_block_2b = pipet(
          volume: create_qty(qty: 198, units: MICROLITERS),
          source: QBIT_JUICE,
          destination: composition.input(OUTPUT_LIBRARY)
        ),
        pipet(
          volume: create_qty(qty: 2, units: MICROLITERS),
          source: composition.input(POOLED_LIBRARY),
          destination: composition.input(OUTPUT_LIBRARY)
        )

      show_block_2c = pipet(
          volume: create_qty(qty: 190, units: MICROLITERS),
          source: QBIT_JUICE,
          destination: S1
        ),
        pipet(
          volume: create_qty(qty: 10, units: MICROLITERS),
          source: composition.input(COMP_B),
          destination: S1
        )

      show_block_2d = pipet(
          volume: create_qty(qty: 190, units: MICROLITERS),
          source: QBIT_JUICE,
          destination: S2
        ),
        pipet(
          volume: create_qty(qty: 10, units: MICROLITERS),
          source: composition.input(COMP_C),
          destination: S2
        )

      show_block_2e = pipet(
          volume: create_qty(qty: 198, units: MICROLITERS),
          source: QBIT_JUICE,
          destination: DIL_10X
        ),
        pipet(
          volume: create_qty(qty: 2, units: MICROLITERS),
          source: DILUTION,
          destination: DIL_10X
        )


      show_block_2f = pipet_up_and_down([composition.input(OUTPUT_LIBRARY),
                                         S1,
                                         S2,
                                         composition.input(DIL_10X)])

      display(
        title: 'Add the Following',
        show_block:[
          show_block_2a,
          show_block_2b,
          show_block_2c,
          show_block_2d,
          show_block_2e,
          show_block_2f
        ]
      )

      sample_vol = qty_display(qty: 2, units: MICROLITERS)
      get_dil_con = show do
        title "Get #{composition.input(DIL_10X)} concentration"
        note 'Go to and turn on Qubit'
        note "Press 'DNA' --> 'dsDNA' --> 'High Sensisitivity' --> 'Read Standards' "
        note "Insert <b>s-1</b> and press 'Read Standard'"
        note "Insert <b>s-2</b> and press 'Read Standard'"
        separator
        note "Press 'Run Samples'"
        note "Set volume to <b>#{sample_vol}"
        note "Set units to #{NANOGRAMS}/#{MICROLITERS}"
        note "Place #{composition.input(DIL_10X)} in th Qubit and press 'run'"
        get('number', var: 'number',
                      label: "Enter concentration in #{NANOGRAMS}/#{MICROLITERS}",
                      default: 0.0)
      end

      get_lib_size = show do
        title 'Get Library Size'
        note "Get a #{CONSUMABLES[STRIP_TUBE8][:name]}"
        note pipet(volume: create_qty(qty:2, units: MICROLITERS),
                   source: composition.input(DIL_10X),
                   destination: CONSUMABLES[STRIP_TUBE8][:name])
        note pipet(volume: create_qty(qty:2, units: MICROLITERS),
                   source: composition.input(SAMPLE_BUFFER),
                   destination: CONSUMABLES[STRIP_TUBE8][:name])
        note vortex([CONSUMABLES[STRIP_TUBE8][:name]])
        note spin_down(items: [CONSUMABLES[STRIP_TUBE8][:name]])
        note show_incubate_items(items: [CONSUMABLES[STRIP_TUBE8][:name]],
                                 time: create_qty(qty: 2, units: MINUTES),
                                 temperature: create_qty(qty: 'Room Temp',
                                                         units: ''))
        separator
        note 'Open <b>2200 Tapestation</b> software on computer'
        note "<b>#{CONSUMABLES[STRIP_TUBE8][:name]}</b> and <b>Agilent HS D1000 ScreenTape</b> into <b>Agilent Technologies 2200 Tapestation</b>."
        separator
        note 'Select Appropriate Well'
        note 'Press <b>RUN</b>'
        separator
        get('number', var: 'number',
                      label: 'Enter Library Size as measured',
                      default: 0.0)
      end

      dil_con = get_dil_con[:number]
      lib_size = get_lib_size[:number]

      if debug
        dil_con = rand(400)
        lib_size = rand(220)
      end

      dil_mol = molarity(q_bit: dil_con, lib_size: lib_size)
      composition.input(DIL_10X).item.associate('molarity', dil_mol)
      composition.input(DIL_10X).item.associate('lib_size', lib_size)
      composition.input(DIL_10X).item.associate("concentration #{NANOGRAMS}/#{MICROLITERS}", lib_size)

      samp_vol = (3.0 * 40.0)/dil_mol
      water_vol = 40.0 - samp_vol

      show do
        title "Create #{composition.input(SEQ_POOL_TUBE)}"
        note pipet(volume: create_qty(qty: samp_vol, units: MICROLITERS),
                   source: composition.input(DIL_10X),
                   destination: composition.input(SEQ_POOL_TUBE))
        note pipet(volume: create_qty(qty: water_vol, units: MICROLITERS),
                   source: composition.input(WATER),
                   destination: composition.input(SEQ_POOL_TUBE))
      end

      show do
        title "Create #{composition.input(FINAL_DILUTION)}"
        note pipet(volume: create_qty(qty: 2, units: MICROLITERS),
                   source: composition.input(SEQ_POOL_TUBE),
                   destination: composition.input(FINAL_DILUTION))
        note pipet(volume: create_qty(qty: 198, units: MICROLITERS),
                   source: QBIT_JUICE,
                   destination: composition.input(FINAL_DILUTION))
      end

      final_con = show do
        title "Get #{composition.input(FINAL_DILUTION)} concentration"
        note 'Go to Qubit'
        note 'Use previously run standards'
        separator
        note "Press 'Run Samples'"
        note "Set volume to <b>#{sample_vol}"
        note "Set units to #{NANOGRAMS}/#{MICROLITERS}"
        note "Place #{composition.input(FINAL_DILUTION)} in th Qubit and press 'run'"
        get('number', var: 'number',
                      label: "Enter concentration in #{NANOGRAMS}/#{MICROLITERS}",
                      default: 0.0)
      end

      store_items([composition.input(SEQ_POOL_TUBE).item,
                   composition.input(DIL_10X).item,
                   composition.input(FINAL_DILUTION).item,
                   composition.input(OUTPUT_LIBRARY).item],
                   location: 'M20')

      operation_history = OperationHistoryFactory.new.from_item(item_id: composition.input(POOLED_LIBRARY).item)

      upload = operation_history.fetch_data(RNA_EXTRACTION_DATA.to_sym).first
      text = upload.url.to_s
      html_text = text.gsub(URI::DEFAULT_PARSER.make_regexp, '<a href="\0">\0</a>').html_safe
      show do
        title 'Download CSV'
        note 'Download the following CSV for use with the Sequencer'
        note html_text
      end

      seq_molarity = molarity(q_bit: final_con[:number], lib_size: lib_size)

      composition.input(SEQ_POOL_TUBE).item.associate('molarity', seq_molarity)
      composition.input(DIL_10X).item.associate('lib_size', lib_size)
      composition.input(DIL_10X).item.associate("concentration #{NANOGRAMS}/#{MICROLITERS}", lib_size)
    end

    {}
  end

  def molarity(q_bit:, lib_size:)
    ( q_bit*( (10**3)/1.0 )*(1.0/649.0)*(1.0/lib_size) )*1000.0
  end

end
